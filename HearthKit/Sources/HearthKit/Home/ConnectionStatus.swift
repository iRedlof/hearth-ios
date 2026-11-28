import Foundation

// MARK: - Home Assistant Connection Status

/// Connection status for Home Assistant integration.
public enum HaConnectionStatus: Sendable, Equatable {
    case notSetUp
    case needsSignIn
    case connected
}

/// Determines the HA connection status from configuration.
/// - Parameter config: The Home Assistant configuration
/// - Returns: The connection status (notSetUp if baseUrl is blank, needsSignIn if not signed in, else connected)
public func haConnectionStatus(_ config: HaConfig) -> HaConnectionStatus {
    if config.baseUrl.trimmingCharacters(in: .whitespaces).isEmpty {
        return .notSetUp
    }
    if !config.isSignedIn {
        return .needsSignIn
    }
    return .connected
}

public extension HaConnectionStatus {
    /// The status tone for UI presentation.
    var tone: StatusTone {
        switch self {
        case .connected: return .ok
        case .needsSignIn: return .warn
        case .notSetUp: return .neutral
        }
    }

    /// The human-readable label for this status.
    var label: String {
        switch self {
        case .connected: return "Connected"
        case .needsSignIn: return "Needs sign-in"
        case .notSetUp: return "Not set up"
        }
    }
}

// MARK: - ChargePoint Connection Status

/// Connection status for ChargePoint integration.
public enum CpConnectionStatus: Sendable, Equatable {
    case notSetUp
    case needsSignIn
    case connected
}

/// Determines the ChargePoint connection status.
/// - Parameters:
///   - signedIn: Whether the user is currently signed in
///   - hasAccount: Whether the user has a ChargePoint account configured
/// - Returns: The connection status (connected if signed in, needsSignIn if has account, else notSetUp)
public func cpConnectionStatus(signedIn: Bool, hasAccount: Bool) -> CpConnectionStatus {
    if signedIn {
        return .connected
    }
    if hasAccount {
        return .needsSignIn
    }
    return .notSetUp
}

/// Single source of truth for ChargePoint sign-in status. The ChargePoint page, the Home
/// Connections row and the Home tile all derive their status from this one function applied to the
/// same stored session, so they cannot disagree. An expired session (ChargePoint signed the user
/// out) is `needsSignIn`, never `connected`.
/// - Parameter session: The persisted ChargePoint session.
/// - Returns: `connected` when signed in; `needsSignIn` when an account exists but is signed out
///   (including expired); `notSetUp` when no account has ever been configured.
public func cpConnectionStatus(for session: CpSession) -> CpConnectionStatus {
    cpConnectionStatus(signedIn: session.isSignedIn,
                       hasAccount: session.userId != 0 || !session.email.isEmpty)
}

public extension CpConnectionStatus {
    /// The status tone for UI presentation.
    var tone: StatusTone {
        switch self {
        case .connected: return .ok
        case .needsSignIn: return .warn
        case .notSetUp: return .neutral
        }
    }

    /// The human-readable label for this status.
    var label: String {
        switch self {
        case .connected: return "Connected"
        case .needsSignIn: return "Needs sign-in"
        case .notSetUp: return "Not set up"
        }
    }
}
