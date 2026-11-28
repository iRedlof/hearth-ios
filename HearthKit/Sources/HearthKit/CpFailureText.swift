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

/// A ChargePoint request whose reply the app must parse. The rawValue is the short, stable,
/// secret-free name shown in Diagnostics ("status", "station list", …).
public enum CpParseRequest: String, Codable, Sendable, Equatable {
    case status
    case stationList = "station list"
}

/// A parse failure that identifies itself. ChargePoint answered with a real HTTP response that could
/// not be interpreted. It carries which request failed, the host, the HTTP status that WAS received
/// (parsing runs only after a 2xx), and a structural description of what was wrong — a key path with
/// expected-vs-found type, or "empty body"/"not JSON"/"HTML page", with a body length. It NEVER
/// carries a value from the response, the token, a cookie, an id, an email or a name.
public struct CpParseError: Error, Equatable, Sendable {
    public let request: CpParseRequest
    public let host: String?
    public let status: Int
    public let detail: String
    public init(request: CpParseRequest, host: String?, status: Int, detail: String) {
        self.request = request; self.host = host; self.status = status; self.detail = detail
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
    if error is CpParseError { return .parse }
    if error is CpObservationError { return .parse }
    return .other
}

/// Best-effort host of a failed read, for diagnostics. Never contains a secret.
public func cpFailureHost(_ error: Error) -> String? {
    if let parse = error as? CpParseError { return parse.host }
    if let ha = error as? HaError, let host = ha.host { return host }
    if let url = error as? URLError { return url.failingURL?.host }
    return nil
}

/// HTTP status carried by a failure. For a parse failure this is the (successful) status of the
/// response that could not be read, so Diagnostics shows it instead of "none".
public func cpFailureStatus(_ error: Error) -> Int? {
    if let parse = error as? CpParseError { return parse.status }
    guard let ha = error as? HaError, ha.code != 0 else { return nil }
    return ha.code
}

/// One os.Logger line per failed ChargePoint read. Host is logged `.private`; status and reason are
/// `.public` and are never secrets (reason is the pure mapping above; status is an HTTP code).
public enum CpLog {
    #if canImport(os)
    private static let logger = Logger(subsystem: "com.rohit.hearth", category: "ChargePoint")
    #endif

    public static func readFailed(host: String?, status: Int?, reason: String, detail: String? = nil) {
        #if canImport(os)
        logger.error("CP read failed host=\(host ?? "unknown", privacy: .private) status=\(status ?? 0, privacy: .public) reason=\(reason, privacy: .public) detail=\(detail ?? "-", privacy: .public)")
        #endif
    }

    /// One os.Logger line per attempted ChargePoint action (tap or Auto arm). Host is `.private`;
    /// action, whether a request was sent, status and the outcome/drop reason are `.public` and are
    /// never secrets (action is an enum raw value, outcome is the fixed secret-free text below).
    public static func actionAttempted(action: String, requestSent: Bool, host: String?,
                                       status: Int?, outcome: String) {
        #if canImport(os)
        logger.log("CP action=\(action, privacy: .public) sent=\(requestSent, privacy: .public) host=\(host ?? "none", privacy: .private) status=\(status ?? 0, privacy: .public) outcome=\(outcome, privacy: .public)")
        #endif
    }
}

/// The last ChargePoint action the phone attempted, described without any secret. Shown in the
/// ChargePoint Diagnostics block and mirrored to one `CpLog.actionAttempted` line. It carries only
/// the action name, a local timestamp, whether a request reached the network, the host, an HTTP
/// status and a fixed, secret-free outcome/drop reason — never a token, cookie, id, email or name.
public struct CpActionRecord: Codable, Sendable, Equatable {
    public let action: String
    public let at: Date
    public let requestSent: Bool
    public let host: String?
    public let status: Int?
    public let outcome: String
    public init(action: String, at: Date, requestSent: Bool, host: String?, status: Int?, outcome: String) {
        self.action = action; self.at = at; self.requestSent = requestSent
        self.host = host; self.status = status; self.outcome = outcome
    }
}

/// Fixed, secret-free outcome text for a completed owned action. Deterministic; no I/O, no values.
public func cpActionOutcomeText(_ outcome: CpOperationOutcome, action: CpOwnedAction) -> String {
    switch outcome {
    case .success:
        switch action {
        case .accept: return "Accepted"
        case .leave: return "Left the waitlist"
        case .snooze: return "Snoozed"
        case .unsnooze: return "Rejoined"
        case .join: return "Joined"
        case .resume: return "Auto resumed"
        case .stop: return "Stopped"
        case .still, .done: return "Answered"
        case .legacy: return "Done"
        }
    case .refused: return "ChargePoint refused it"
    case .uncertain: return "No response"
    case .cancelledBeforeAdmission: return "Details changed before sending"
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
    /// The request that failed, for a parse failure (e.g. "status"). Nil for non-parse failures.
    public let request: String?
    /// A structural description of a parse failure (key path + expected/found type, or
    /// "empty body"/"not JSON"/"HTML page" with a body length). Never a value. Nil otherwise.
    public let detail: String?
    public init(at: String, host: String?, status: Int?, reason: String,
                request: String? = nil, detail: String? = nil) {
        self.at = at; self.host = host; self.status = status; self.reason = reason
        self.request = request; self.detail = detail
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
    /// The last action the phone attempted (tap or Auto arm), secret-free. Nil if none recorded.
    public let lastAction: CpActionRecord?
    public let appVersion: String
    public let build: String

    public init(tokenPresent: Bool, userIDPresent: Bool, expired: Bool, minutesLeft: Int?,
                lastAttempt: CpDiagnosticsAttempt?, lastAction: CpActionRecord? = nil,
                appVersion: String, build: String) {
        self.tokenPresent = tokenPresent; self.userIDPresent = userIDPresent; self.expired = expired
        self.minutesLeft = minutesLeft; self.lastAttempt = lastAttempt; self.lastAction = lastAction
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
        if let request = attempt.request { lines.append("Request: \(request)") }
        if let detail = attempt.detail { lines.append("Detail: \(detail)") }
    } else {
        lines.append("Last read: none recorded")
    }
    if let action = input.lastAction {
        lines.append("Last action: \(action.action) at \(HearthTimeFormatter.shortTime(action.at))")
        lines.append("Request sent: \(yesNo(action.requestSent))")
        if action.requestSent {
            lines.append("Action host: \(action.host ?? "unknown")")
            lines.append("Action HTTP status: \(action.status.map(String.init) ?? "none")")
        }
        lines.append("Outcome: \(action.outcome)")
    } else {
        lines.append("Last action: none recorded")
    }
    lines.append("App version: \(input.appVersion) (\(input.build))")
    return lines.joined(separator: "\n")
}
