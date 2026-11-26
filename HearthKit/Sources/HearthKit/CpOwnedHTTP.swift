import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

/// Prepared tasks start suspended. The store admits one application start, not one physical transmission.
public protocol CpPreparedRequest: Sendable {
    func start()
    func cancel()
    func response() async throws -> (Data, HTTPURLResponse)
}

public protocol CpOwnedTransport: Sendable {
    func prepare(_ request: URLRequest) throws -> any CpPreparedRequest
}

public struct CpHTTPResult: Sendable {
    public let body: String
    public let admission: CpDispatchAdmission
}

public struct CpOwnedHTTP: Sendable {
    public let store: CpStateStore
    public let gate: CpRequestGate
    public let transport: any CpOwnedTransport
    private let onAlert: @Sendable (CpAlert, CpStoreSnapshot) -> Void

    public init(store: CpStateStore, directory: URL, transport: any CpOwnedTransport = CpURLSessionTransport(),
                onAlert: @escaping @Sendable (CpAlert, CpStoreSnapshot) -> Void = { _, _ in }) {
        self.store = store; gate = CpRequestGate(directory: directory); self.transport = transport
        self.onAlert = onAlert
    }

    public func send(authority: CpRequestAuthority, purpose: CpRequestPurpose,
                     now: @Sendable () -> Date = { .now }) async throws -> CpHTTPResult {
        let cancellation = CpRequestCancellation()
        return try await withTaskCancellationHandler {
            try await gate.withLock {
                try Task.checkCancellation()
                guard let credential = try store.requestCredential(authority: authority, purpose: purpose, now: now()) else {
                    throw CpFeedback.detailsChanged
                }
                let prepared = try transport.prepare(try cpOwnedRequest(credential, purpose: purpose))
                guard cancellation.install(prepared) else { prepared.cancel(); throw CancellationError() }
                let admission: CpDispatchAdmission?
                do {
                    admission = try cancellation.admit {
                        try store.authorizeAndStart(credential: credential, purpose: purpose, now: now()) { _ in prepared.start() }
                    }
                } catch { prepared.cancel(); throw error }
                guard let admission else { prepared.cancel(); throw CpFeedback.detailsChanged }
                let (data, response) = try await prepared.response()
                // Cookie ownership is checked before the gate opens for another owned request.
                let cookie = response.value(forHTTPHeaderField: "Set-Cookie").flatMap { CpClient.cookieValue($0, "coulomb_sess") }
                guard try store.commitResponse(admission: admission,
                    metadata: CpResponseMetadata(status: response.statusCode, cookie: cookie), now: now(),
                    synchronousAlert: onAlert) else {
                    throw CpFeedback.detailsChanged
                }
                guard (200..<300).contains(response.statusCode) else {
                    throw HaError(response.statusCode == 403 ? CP_REFUSED : "ChargePoint replied \(response.statusCode)",
                        code: response.statusCode)
                }
                try Task.checkCancellation()
                guard let body = String(data: data, encoding: .utf8) else { throw CpObservationError.malformed }
                return CpHTTPResult(body: body, admission: admission)
            }
        } onCancel: {
            cancellation.cancel()
        }
    }
}

public struct CpRequestGate: Sendable {
    public let directory: URL
    public init(directory: URL) { self.directory = directory }
    public func withLock<T: Sendable>(_ body: @Sendable () async throws -> T) async throws -> T {
        try Task.checkCancellation()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let path = directory.appendingPathComponent("cp-request.lock")
        let descriptor = open(path.path, O_CREAT | O_RDWR | O_NOFOLLOW, 0o600)
        guard descriptor >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        defer { close(descriptor) }
        var info = stat()
        guard fstat(descriptor, &info) == 0, (info.st_mode & mode_t(S_IFMT)) == mode_t(S_IFREG) else {
            throw CpStateStoreError.corrupt
        }
        var attributes: [FileAttributeKey: Any] = [.posixPermissions: 0o600]
        #if os(iOS)
        attributes[.protectionKey] = FileProtectionType.completeUntilFirstUserAuthentication
        #endif
        try FileManager.default.setAttributes(attributes, ofItemAtPath: path.path)
        while flock(descriptor, LOCK_EX | LOCK_NB) != 0 {
            guard errno == EWOULDBLOCK || errno == EAGAIN || errno == EINTR else {
                throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            }
            try await Task.sleep(nanoseconds: 25_000_000)
        }
        defer { _ = flock(descriptor, LOCK_UN) }
        try Task.checkCancellation()
        return try await body()
    }
}

public struct CpURLSessionTransport: CpOwnedTransport {
    public init() {}
    public func prepare(_ request: URLRequest) throws -> any CpPreparedRequest {
        CpURLPreparedRequest(request)
    }
}

private final class CpRequestCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    private var task: (any CpPreparedRequest)?
    func install(_ value: any CpPreparedRequest) -> Bool {
        lock.withLock { guard !cancelled else { return false }; task = value; return true }
    }
    func admit(_ body: () throws -> CpDispatchAdmission?) throws -> CpDispatchAdmission? {
        try lock.withLock {
            guard !cancelled else { throw CancellationError() }
            return try body()
        }
    }
    func cancel() {
        let value = lock.withLock { cancelled = true; return task }
        value?.cancel() // Never call cancellation or resume a continuation while holding this lock.
    }
}

private final class CpHTTPCompletion: @unchecked Sendable {
    private let lock = NSLock()
    private var result: Result<(Data, HTTPURLResponse), Error>?
    private var continuation: CheckedContinuation<(Data, HTTPURLResponse), Error>?
    func complete(_ value: Result<(Data, HTTPURLResponse), Error>) {
        let waiter = lock.withLock {
            guard result == nil else { return Optional<CheckedContinuation<(Data, HTTPURLResponse), Error>>.none }
            result = value
            let waiter = continuation; continuation = nil
            return waiter
        }
        waiter?.resume(with: value)
    }
    func response() async throws -> (Data, HTTPURLResponse) {
        try await withCheckedThrowingContinuation { waiter in
            let completed = lock.withLock { () -> Result<(Data, HTTPURLResponse), Error>? in
                if let result { return result }
                continuation = waiter
                return Optional<Result<(Data, HTTPURLResponse), Error>>.none
            }
            if let completed { waiter.resume(with: completed) }
        }
    }
}

private final class CpNoFollowupDelegate: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        completionHandler(nil)
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping @Sendable (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        #if canImport(Security)
        if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust {
            completionHandler(.performDefaultHandling, nil)
            return
        }
        #endif
        completionHandler(.cancelAuthenticationChallenge, nil)
    }
}

private final class CpURLPreparedRequest: CpPreparedRequest, @unchecked Sendable {
    private let completion = CpHTTPCompletion()
    private let session: URLSession
    private let task: URLSessionDataTask
    init(_ request: URLRequest) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCredentialStorage = nil
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        session = URLSession(configuration: configuration, delegate: CpNoFollowupDelegate(), delegateQueue: nil)
        let completion = self.completion
        task = session.dataTask(with: request) { data, response, error in
            if let error { completion.complete(.failure(error)); return }
            guard let data, let response = response as? HTTPURLResponse else {
                completion.complete(.failure(CpObservationError.malformed)); return
            }
            completion.complete(.success((data, response)))
        }
    }
    deinit { session.invalidateAndCancel() }
    func start() { task.resume() }
    func cancel() { task.cancel() }
    func response() async throws -> (Data, HTTPURLResponse) { try await completion.response() }
}

/// Construct the exact existing provider payload from the captured credential and typed purpose.
func cpOwnedRequest(_ credential: CpRequestCredential, purpose: CpRequestPurpose) throws -> URLRequest {
    var path: String
    var method = "POST"
    var json: [String: Any]?
    var form: String?
    switch purpose {
    case .status:
        path = CpClient.MAP + "v2"; json = ["user_id": credential.userID, "user_status": ["mfhs": [:]]]
    case .stations(let bounds):
        path = CpClient.MAP + "v2"
        json = ["user_id": credential.userID, "map_data": ["sw_lon": bounds.swLon, "ne_lat": bounds.neLat,
            "ne_lon": bounds.neLon, "sw_lat": bounds.swLat, "screen_width": 1080, "screen_height": 2048,
            "waitlist": true, "filter": [:], "mfhs": [:]]]
    case .inline:
        path = CpClient.ACCOUNT + "v1/driver/station/waitlist/inlinestatus"; method = "GET"
    case .allowance(let token):
        path = CpClient.PORTAL + "community/get_notification_detail/" + cpPathComponent(token); form = ""
    case .charging(let id):
        path = CpClient.DRIVER + "v1/sessions/\(id)"
        json = ["user_id": credential.userID, "charging_status": ["session_id": id, "mfhs": []]]
    case .profile:
        path = CpClient.ACCOUNT + "v1/driver/profile/user"; method = "GET"
    case .renew:
        path = CpClient.WEBSERVICES + "mobileapi/v5"; json = ["user_id": credential.userID]
    case .mutation(let action):
        switch action {
        case .join:
            guard let location = credential.location else { throw CpFeedback.detailsChanged }
            path = CpClient.ACCOUNT + "v1/driver/station/waitlist/join"; json = cpJoinBody(location)
        case .leave:
            path = CpClient.ACCOUNT + "v1/driver/station/waitlist/leave"; method = "DELETE"
        case .accept:
            path = CpClient.PORTAL + "backend.php/community/acceptV2"; form = ""
        case .snooze:
            path = CpClient.PORTAL + "backend.php/community/snoozeV2"; form = "snoozeTime=\(CP_AUTO_SNOOZE_SECONDS)"
        case .unsnooze:
            path = CpClient.PORTAL + "backend.php/community/unsnoozeTheDriver"; form = ""
        case .stop:
            guard let id = credential.target?.sessionID else { throw CpFeedback.sessionChanged }
            path = CpClient.ACCOUNT + "v1/driver/station/stopSession"
            json = ["sessionId": id, "deviceData": CpClient.deviceData(credential.udid)]
        case .still, .done:
            guard let target = credential.target, let token = target.token else { throw CpFeedback.offerChanged }
            path = CpClient.PORTAL + (target.phase == "CHARGING_FAULT" ? "fr" : "community/process_rehold")
                + "/\(action == .still ? 1 : 0)/" + cpPathComponent(token)
            form = ""
        case .resume, .legacy: throw CpFeedback.detailsChanged
        }
    case .acknowledgement(let id):
        path = CpClient.ACCOUNT + "v1/driver/station/session/ack"
        json = ["ackId": id, "action": "stop_session"]
    }
    guard let url = URL(string: path) else { throw CpObservationError.malformed }
    var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
    request.httpShouldHandleCookies = false
    request.httpMethod = method
    request.setValue("coulomb_sess=\(credential.token)", forHTTPHeaderField: "Cookie")
    request.setValue(credential.token, forHTTPHeaderField: "cp-session-token")
    request.setValue("CP_SESSION_TOKEN", forHTTPHeaderField: "cp-session-type")
    request.setValue("NA-US", forHTTPHeaderField: "cp-region")
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    if let json {
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: json)
    } else if let form {
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data(form.utf8)
    }
    return request
}

private func cpPathComponent(_ value: String) -> String {
    value.addingPercentEncoding(withAllowedCharacters: CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_.~"))) ?? ""
}
