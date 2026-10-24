import Foundation

public struct HaError: Error, Sendable, Equatable {
    public let message: String
    public let code: Int
    public init(_ message: String, code: Int = 0) { self.message = message; self.code = code }
}

/// Short-lived access tokens cached in-memory, keyed by refresh token, renewed 60s before expiry.
/// Ported from Android `HaAuth`. An actor for Swift-6 concurrency safety (replaces the Kotlin Mutex).
public actor HaAuth {
    public static let shared = HaAuth()
    public static let redirect = "hearth://auth-callback"
    public static func clientId(_ baseUrl: String) -> String { baseUrl.trimmedTrailingSlash + "/dashboard/" }

    /// The Home Assistant browser sign-in URL (same params as the Android app). Open this in an
    /// `ASWebAuthenticationSession`; HA redirects to `redirect` with `?code=...&state=...`.
    public static func authorizeURL(_ baseUrl: String, state: String) -> URL? {
        var c = URLComponents(string: baseUrl.trimmedTrailingSlash + "/auth/authorize")
        c?.queryItems = [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: clientId(baseUrl)),
            URLQueryItem(name: "redirect_uri", value: redirect),
            URLQueryItem(name: "state", value: state),
        ]
        return c?.url
    }

    private var cached: (refresh: String, tokens: HaTokens)?

    public func accessToken(_ config: HaConfig) async throws -> String {
        let nowMs = Date().timeIntervalSince1970 * 1000
        if let c = cached, c.refresh == config.refreshToken, c.tokens.expiresAt - 60_000 > nowMs {
            return c.tokens.access
        }
        let t = try await Self.renew(config.baseUrl, config.refreshToken)
        cached = (config.refreshToken, t)
        return t.access
    }

    public func forget() { cached = nil }

    public static func exchange(_ baseUrl: String, _ code: String) async throws -> HaTokens {
        try await token(baseUrl, ["grant_type": "authorization_code", "code": code, "client_id": clientId(baseUrl)])
    }
    public static func renew(_ baseUrl: String, _ refresh: String) async throws -> HaTokens {
        try await token(baseUrl, ["grant_type": "refresh_token", "refresh_token": refresh, "client_id": clientId(baseUrl)])
    }

    private static func token(_ baseUrl: String, _ form: [String: String]) async throws -> HaTokens {
        guard let url = URL(string: baseUrl.trimmedTrailingSlash + "/auth/token") else { throw HaError("Bad URL") }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 10
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.httpBody = form.map { "\($0.key)=\($0.value.urlFormEncoded)" }.joined(separator: "&").data(using: .utf8)
        let (data, resp) = try await URLSession.shared.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(code) else {
            throw HaError(code == 400 ? "Signed out: sign in again" : "Sign-in failed (\(code))", code: code)
        }
        let o = ((try? JSONSerialization.jsonObject(with: data)) as? [String: Any]) ?? [:]
        guard let access = o["access_token"] as? String else { throw HaError("Sign-in failed (no token)") }
        let expiresIn = (o["expires_in"] as? Double) ?? (o["expires_in"] as? Int).map(Double.init) ?? 1800
        let refreshTok = (o["refresh_token"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        return HaTokens(access: access, expiresAt: Date().timeIntervalSince1970 * 1000 + expiresIn * 1000, refresh: refreshTok)
    }
}

public struct HaTokens: Sendable, Equatable {
    public let access: String
    public let expiresAt: Double   // milliseconds since epoch
    public let refresh: String?
}

/// Home Assistant REST client. Ported from Android `HaClient.kt`. The car widget uses only `template`.
public struct HaClient: Sendable {
    public let config: HaConfig
    public init(_ config: HaConfig) { self.config = config }

    /// Renders a Home Assistant template (`POST /api/template`); the reply is the raw rendered string.
    public func template(_ template: String) async throws -> String {
        let body = try JSONSerialization.data(withJSONObject: ["template": template])
        return try await request("POST", "/api/template", body)
    }

    public func allStatesJson() async throws -> String { try await request("GET", "/api/states", nil) }
    public func stateJson(_ entityId: String) async throws -> String { try await request("GET", "/api/states/\(entityId)", nil) }

    private func bearer() async throws -> String {
        config.token.isEmpty ? try await HaAuth.shared.accessToken(config) : config.token
    }

    private func request(_ method: String, _ path: String, _ body: Data?) async throws -> String {
        let token = try await bearer()
        guard let url = URL(string: config.baseUrl.trimmedTrailingSlash + path) else { throw HaError("Bad URL") }
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.timeoutInterval = 10
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let body { req.httpBody = body }
        let (data, resp) = try await URLSession.shared.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        if code == 401 {
            await HaAuth.shared.forget()
            throw HaError(config.isSignedIn ? "Signed out: sign in again" : "Sign-in rejected: check the token", code: code)
        }
        if code == 404 { throw HaError("Not found: check the entity", code: code) }
        guard (200..<300).contains(code) else { throw HaError("Home Assistant replied \(code)", code: code) }
        return String(data: data, encoding: .utf8) ?? ""
    }
}

/// Classify a thrown error into a user-facing line (network vs HA refusal). Ported from `friendlyError`.
public func friendlyError(_ error: Error) -> String {
    if let ha = error as? HaError { return ha.message }
    if let urlErr = error as? URLError {
        switch urlErr.code {
        case .cannotFindHost, .cannotConnectToHost, .timedOut, .notConnectedToInternet,
             .networkConnectionLost, .secureConnectionFailed, .dnsLookupFailed:
            return "Can't reach Home Assistant"
        default: return "Can't reach Home Assistant"
        }
    }
    return "Couldn't check the car"
}

/// Whether the error should route to the Settings CTA (vs a Retry). Ported from `beaconNeedsSettings`.
public func beaconNeedsSettings(_ error: String?) -> Bool {
    guard let e = error?.lowercased() else { return false }
    return e.hasPrefix("set up") || e.contains("sign in") || e.contains("sign-in")
        || e.contains("check the entity") || e.contains("check the token")
}

extension String {
    var trimmedTrailingSlash: String {
        var s = Substring(self)
        while s.hasSuffix("/") { s = s.dropLast() }
        return String(s)
    }
    var urlFormEncoded: String {
        addingPercentEncoding(withAllowedCharacters: CharacterSet(charactersIn:
            "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")) ?? self
    }
}
