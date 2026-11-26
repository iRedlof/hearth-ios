import Foundation

/// The persisted ChargePoint web session. Ported from Android `CpSession` — the `coulomb_sess`
/// cookie IS the credential (no OAuth/bearer); it rolls on every response. `userId`/`email` come
/// from the profile call at sign-in. `expired` = full sign-out needed; `joinExpired` = view-only
/// (the account host dropped but the map still answers).
public struct CpSession: Sendable, Equatable, Codable {
    public var token: String
    public var userId: Int64
    public var email: String
    public var expired: Bool
    public var joinExpired: Bool
    public var renewedAt: Int64   // ms of last 6-month cookie mint

    public init(token: String = "", userId: Int64 = 0, email: String = "", expired: Bool = false,
                joinExpired: Bool = false, renewedAt: Int64 = 0) {
        self.token = token; self.userId = userId; self.email = email
        self.expired = expired; self.joinExpired = joinExpired; self.renewedAt = renewedAt
    }

    public var isSignedIn: Bool { !token.isEmpty && userId != 0 && !expired }
}

public let CP_REFUSED = "ChargePoint refused the request"

/// ChargePoint cloud client. Ported from Android `CpClient` (ChargePoint.kt). Every request carries
/// the `coulomb_sess` value twice (Cookie header + `cp-session-token`) plus the session-type/region
/// headers; cookies are NOT handled automatically so we can read the rolled `coulomb_sess` from each
/// `Set-Cookie` and persist it via `onToken`. `send` returns the raw body string for the existing
/// forgiving-JSON parse layer (`cpWaitlistFrom`, `cpStationsFrom`, …). The transport is injectable.
public struct CpClient: Sendable {
    public typealias Transport = @Sendable (URLRequest) async throws -> (Data, HTTPURLResponse)

    static let MAP = "https://mc.chargepoint.com/map-prod/"
    static let ACCOUNT = "https://account.chargepoint.com/account/"
    static let PORTAL = "https://na.chargepoint.com/"
    static let DRIVER = "https://internal-api-us.chargepoint.com/driver-bff/"
    static let WEBSERVICES = "https://webservices.chargepoint.com/backend.php/"

    public let token: String
    public let userId: Int64
    let onToken: @Sendable (String) -> Void
    let transport: Transport

    public init(token: String, userId: Int64,
                onToken: @escaping @Sendable (String) -> Void = { _ in },
                transport: @escaping Transport = CpClient.urlSessionTransport) {
        self.token = token; self.userId = userId; self.onToken = onToken; self.transport = transport
    }

    public static let urlSessionTransport: Transport = { req in
        let cfg = URLSessionConfiguration.ephemeral
        cfg.httpCookieStorage = nil
        cfg.httpShouldSetCookies = false
        let (data, resp) = try await URLSession(configuration: cfg).data(for: req)
        guard let http = resp as? HTTPURLResponse else { throw HaError("No HTTP response") }
        return (data, http)
    }

    // MARK: reads (return the raw body for the parse layer)
    public func userStatus() async throws -> String {
        try await send("POST", Self.MAP + "v2", json: ["user_id": userId, "user_status": ["mfhs": [:]]])
    }
    public func stations(_ b: CpBounds) async throws -> String {
        try await send("POST", Self.MAP + "v2", json: ["user_id": userId, "map_data": [
            "sw_lon": b.swLon, "ne_lat": b.neLat, "ne_lon": b.neLon, "sw_lat": b.swLat,
            "screen_width": 1080, "screen_height": 2048, "waitlist": true, "filter": [:], "mfhs": [:]]])
    }
    public func profile() async throws -> String {
        try await send("GET", Self.ACCOUNT + "v1/driver/profile/user")
    }
    public func renewSession() async throws {
        _ = try await send("POST", Self.WEBSERVICES + "mobileapi/v5", json: ["user_id": userId])
    }
    public func inlineStatus() async throws -> String {
        try await send("GET", Self.ACCOUNT + "v1/driver/station/waitlist/inlinestatus")
    }
    public func snoozeDetail(offerToken: String) async throws -> String {
        try await send("POST", Self.PORTAL + "community/get_notification_detail/\(offerToken)", form: "")
    }
    public func chargingDetail(sessionId: Int64) async throws -> String {
        try await send("POST", Self.DRIVER + "v1/sessions/\(sessionId)",
                       json: ["user_id": userId, "charging_status": ["session_id": sessionId, "mfhs": []]])
    }

    // MARK: commands
    public func join(_ body: [String: Any]) async throws {
        _ = try await send("POST", Self.ACCOUNT + "v1/driver/station/waitlist/join", json: body)
    }
    public func leave() async throws {
        _ = try await send("DELETE", Self.ACCOUNT + "v1/driver/station/waitlist/leave")
    }
    public func accept() async throws {
        try requireAnswered(await send("POST", Self.PORTAL + "backend.php/community/acceptV2", form: ""))
    }
    public func snooze(seconds: Int) async throws {
        try requireAnswered(await send("POST", Self.PORTAL + "backend.php/community/snoozeV2", form: "snoozeTime=\(seconds)"))
    }
    public func unsnooze() async throws {
        try requireAnswered(await send("POST", Self.PORTAL + "backend.php/community/unsnoozeTheDriver", form: ""))
    }
    public func start(deviceId: Int64, connectorId: Int?, udid: String) async throws {
        var body: [String: Any] = ["deviceId": deviceId, "deviceData": Self.deviceData(udid)]
        if let connectorId, connectorId > 0 { body["connectorId"] = connectorId }
        let ack = try await send("POST", Self.ACCOUNT + "v1/driver/station/startsession", json: body)
        try await ackLoop(ackId: ackId(ack), action: "start_session")
    }
    public func stop(sessionId: Int64, deviceId: Int64?, port: Int?, udid: String) async throws {
        var body: [String: Any] = ["sessionId": sessionId, "deviceData": Self.deviceData(udid)]
        if let deviceId { body["deviceId"] = deviceId }
        if let port { body["portNumber"] = port }
        let ack = try await send("POST", Self.ACCOUNT + "v1/driver/station/stopSession", json: body)
        try await ackLoop(ackId: ackId(ack), action: "stop_session")
    }

    /// Answer ChargePoint's "still charging?" (CHARGING_FAULT) / "unplugged?" (DIB_PLUG_OUT) prompt —
    /// `yes` keeps the hold. Routes to `fr` for a fault, else `process_rehold`. Ported from Android still/done.
    public func answerStill(yes: Bool, token: String, fault: Bool) async throws {
        let path = fault ? "fr/\(yes ? 1 : 0)/\(token)" : "community/process_rehold/\(yes ? 1 : 0)/\(token)"
        _ = try await send("POST", Self.PORTAL + path, form: "")
    }

    /// Poll the ack endpoint up to 75× every 750ms until ChargePoint confirms (non-2xx until then).
    private func ackLoop(ackId: Int64, action: String) async throws {
        for _ in 0..<75 {
            if (try? await send("POST", Self.ACCOUNT + "v1/driver/station/session/ack",
                                json: ["ackId": ackId, "action": action])) != nil { return }
            try await Task.sleep(nanoseconds: 750_000_000)
        }
        throw HaError("ChargePoint didn't confirm in time")
    }

    // MARK: plumbing
    private func send(_ method: String, _ urlString: String, json: [String: Any]? = nil,
                      form: String? = nil) async throws -> String {
        guard let url = URL(string: urlString) else { throw HaError("Bad URL") }
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.timeoutInterval = 15
        req.setValue("coulomb_sess=\(token)", forHTTPHeaderField: "Cookie")
        req.setValue(token, forHTTPHeaderField: "cp-session-token")
        req.setValue("CP_SESSION_TOKEN", forHTTPHeaderField: "cp-session-type")
        req.setValue("NA-US", forHTTPHeaderField: "cp-region")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        if let json {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONSerialization.data(withJSONObject: json)
        } else if let form {
            req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            req.httpBody = form.data(using: .utf8)
        }
        let (data, resp) = try await transport(req)
        if let header = resp.value(forHTTPHeaderField: "Set-Cookie"),
           let rolled = Self.cookieValue(header, "coulomb_sess"), rolled != token {
            onToken(rolled)
        }
        switch resp.statusCode {
        case 200..<300: return String(data: data, encoding: .utf8) ?? ""
        case 401: throw HaError("Signed out: sign in again", code: 401)
        case 403: throw HaError(CP_REFUSED, code: 403)
        default: throw HaError("ChargePoint replied \(resp.statusCode)", code: resp.statusCode)
        }
    }

    /// Android `cpAnswered`: result==true && response.success != false, else throw the message.
    private func requireAnswered(_ body: String) throws {
        let r = Self.object(body)
        let ok = (r["result"] as? Bool) ?? false
        let response = r["response"] as? [String: Any]
        let success = (response?["success"] as? Bool) ?? true
        if !(ok && success) {
            throw HaError((response?["errorMessage"] as? String) ?? (r["message"] as? String) ?? CP_REFUSED)
        }
    }

    private func ackId(_ body: String) -> Int64 {
        let r = Self.object(body)
        if let i = r["ackId"] as? Int64 { return i }
        if let i = r["ackId"] as? Int { return Int64(i) }
        return 0
    }

    private static func object(_ body: String) -> [String: Any] {
        (try? JSONSerialization.jsonObject(with: Data(body.utf8))) as? [String: Any] ?? [:]
    }

    static func deviceData(_ udid: String) -> [String: Any] {
        ["manufacturer": "Apple", "model": "iPhone", "type": "iOS", "udid": udid,
         "version": "1.0", "notificationId": "", "notificationIdType": ""]
    }

    /// Extract a cookie value by name from a `Set-Cookie` header (value runs to the next `;`).
    static func cookieValue(_ header: String, _ name: String) -> String? {
        guard let r = header.range(of: "\(name)=") else { return nil }
        let value = header[r.upperBound...].prefix { $0 != ";" && $0 != "," && $0 != " " }
        return value.isEmpty ? nil : String(value)
    }
}

/// Parse the `profile/user` response into (userId, email) — used at sign-in to validate the captured
/// cookie and name the account. Ported from Android `cpProfileFrom`. Returns nil while the login page
/// is still redirecting (no user yet), which the sign-in view treats as "keep polling".
public func cpProfileFrom(_ json: String?) -> (userId: Int64, email: String)? {
    guard let json, let data = json.data(using: .utf8),
          let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let user = obj["user"] as? [String: Any] else { return nil }
    let uid = (user["userId"] as? Int64) ?? Int64((user["userId"] as? Int) ?? 0)
    guard uid != 0 else { return nil }
    let email = (user["email"] as? String) ?? (user["emailAddress"] as? String)
        ?? (user["username"] as? String) ?? ""
    return (uid, email)
}
