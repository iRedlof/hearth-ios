import Foundation
#if canImport(os)
import os
#endif

/// Classification of a failed ChargePoint read. This keeps *what* failed so the UI and diagnostics
/// can show a real reason instead of a generic "Couldn't check". The classification is the only
/// thing persisted alongside the stored failure; no secret (token, cookie, email) is ever captured.
public enum CpReadFailureKind: Codable, Sendable, Equatable {
    /// ChargePoint rejected the session (HTTP 401). Retrying will not help — the user must sign in.
    case signedOut
    /// ChargePoint refused the request (HTTP 403).
    case refused
    /// Any other non-success HTTP status (e.g. a 302 redirect iOS does not follow, or a 5xx).
    case http(Int)
    /// A transport/connectivity failure (no response from ChargePoint).
    case network
    /// ChargePoint answered but the body could not be read/parsed.
    case parse
    /// An unclassified failure.
    case other
}

/// What the user is shown for a read failure: a short human reason plus whether retrying can help.
public struct CpFailurePresentation: Sendable, Equatable {
    public let reason: String
    public let canRetry: Bool
    public init(reason: String, canRetry: Bool) {
        self.reason = reason
        self.canRetry = canRetry
    }

    /// The widget / page secondary line. "Refresh to retry" is appended only when retrying can help.
    public var line: String { canRetry ? "\(reason) · Refresh to retry" : reason }
    /// The accessibility / status-description sentence form.
    public var statusDescription: String { canRetry ? "\(reason). Refresh to retry." : reason }
}

/// Pure mapping from a classified read failure to the text the user sees. Tested in isolation.
public func cpFailurePresentation(_ kind: CpReadFailureKind) -> CpFailurePresentation {
    switch kind {
    case .signedOut:
        // Retrying a 401 cannot recover; the user must sign in again.
        return CpFailurePresentation(reason: "ChargePoint signed you out", canRetry: false)
    case .refused:
        return CpFailurePresentation(reason: CP_REFUSED, canRetry: false)
    case let .http(status):
        return CpFailurePresentation(reason: "ChargePoint replied \(status)", canRetry: true)
    case .network:
        return CpFailurePresentation(reason: "No connection", canRetry: true)
    case .parse:
        return CpFailurePresentation(reason: "Couldn't read ChargePoint's reply", canRetry: true)
    case .other:
        return CpFailurePresentation(reason: "Couldn't check ChargePoint", canRetry: true)
    }
}

/// Classify a thrown error from the owned ChargePoint read pipeline. Deterministic; no I/O.
public func cpClassifyReadFailure(_ error: Error) -> CpReadFailureKind {
    if let ha = error as? HaError {
        switch ha.code {
        case 401: return .signedOut
        case 403: return .refused
        case let code where code != 0: return .http(code)
        default: return .other
        }
    }
    if error is URLError { return .network }
    if error is CpObservationError { return .parse }
    return .other
}

/// Best-effort host of a failed read, for diagnostics. Never contains a secret.
public func cpFailureHost(_ error: Error) -> String? {
    if let ha = error as? HaError, let host = ha.host { return host }
    if let url = error as? URLError { return url.failingURL?.host }
    return nil
}

/// HTTP status carried by a failure, if the error was an HTTP response (nil for transport/parse).
public func cpFailureStatus(_ error: Error) -> Int? {
    guard let ha = error as? HaError, ha.code != 0 else { return nil }
    return ha.code
}

/// One os.Logger line per failed ChargePoint read. Host is logged `.private`; status and reason are
/// `.public` and are never secrets (reason is the pure mapping above; status is an HTTP code).
public enum CpLog {
    #if canImport(os)
    private static let logger = Logger(subsystem: "com.rohit.hearth", category: "ChargePoint")
    #endif

    public static func readFailed(host: String?, status: Int?, reason: String) {
        #if canImport(os)
        logger.error("CP read failed host=\(host ?? "unknown", privacy: .private) status=\(status ?? 0, privacy: .public) reason=\(reason, privacy: .public)")
        #endif
    }
}

/// User-facing reason for a failed ChargePoint action (e.g. arming Auto-waitlist). Uses the same
/// failure mapping as reads so the page shows consistent wording, while preserving the specific
/// ownership feedback messages (details/offer/session changed) that are not transport failures.
public func cpActionErrorText(_ error: Error) -> String {
    if let feedback = error as? CpFeedback { return feedback.message }
    let kind = cpClassifyReadFailure(error)
    if case .other = kind { return friendlyError(error) }
    return cpFailurePresentation(kind).reason
}

// MARK: - Diagnostics

/// The last read attempt the app can describe without secrets.
public struct CpDiagnosticsAttempt: Sendable, Equatable {
    public let at: String        // already-formatted local time, e.g. "9:41 AM"
    public let host: String?
    public let status: Int?
    public let reason: String
    public init(at: String, host: String?, status: Int?, reason: String) {
        self.at = at; self.host = host; self.status = status; self.reason = reason
    }
}

/// Everything the ChargePoint Diagnostics block prints. It carries ONLY booleans, counts, a host,
/// an HTTP status, mapped reason text and version strings — never the token, cookie, user id value,
/// email or account name. The builder below therefore cannot leak a secret.
public struct CpDiagnosticsInput: Sendable, Equatable {
    public let tokenPresent: Bool
    public let userIDPresent: Bool
    public let expired: Bool
    public let minutesLeft: Int?
    public let lastAttempt: CpDiagnosticsAttempt?
    public let appVersion: String
    public let build: String

    public init(tokenPresent: Bool, userIDPresent: Bool, expired: Bool, minutesLeft: Int?,
                lastAttempt: CpDiagnosticsAttempt?, appVersion: String, build: String) {
        self.tokenPresent = tokenPresent; self.userIDPresent = userIDPresent; self.expired = expired
        self.minutesLeft = minutesLeft; self.lastAttempt = lastAttempt
        self.appVersion = appVersion; self.build = build
    }
}

/// Pure builder for the copyable diagnostics text. Deterministic; no secrets by construction.
public func cpDiagnosticsText(_ input: CpDiagnosticsInput) -> String {
    func yesNo(_ value: Bool) -> String { value ? "Yes" : "No" }
    var lines: [String] = []
    lines.append("ChargePoint diagnostics")
    lines.append("Token present: \(yesNo(input.tokenPresent))")
    lines.append("User ID present: \(yesNo(input.userIDPresent))")
    lines.append("Expired: \(yesNo(input.expired))")
    if input.tokenPresent {
        if let minutes = input.minutesLeft {
            lines.append("Token valid for: \(minutes) min")
        } else {
            lines.append("Token valid for: unknown")
        }
    }
    if let attempt = input.lastAttempt {
        lines.append("Last read: \(attempt.at)")
        lines.append("Host: \(attempt.host ?? "unknown")")
        lines.append("HTTP status: \(attempt.status.map(String.init) ?? "none")")
        lines.append("Reason: \(attempt.reason)")
    } else {
        lines.append("Last read: none recorded")
    }
    lines.append("App version: \(input.appVersion) (\(input.build))")
    return lines.joined(separator: "\n")
}
