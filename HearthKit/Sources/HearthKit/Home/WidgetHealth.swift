import Foundation

/// Health status for widgets, comparable by severity (higher rawValue = more urgent).
public enum WidgetHealth: Int, Sendable, CaseIterable, Comparable {
    case ok = 0
    case paused
    case stale
    case offline
    case setup
    case needsSignIn
    case error

    /// Whether this health status should sort before `.ok` items.
    public var sortsFirst: Bool {
        self != .ok
    }

    public static func < (lhs: WidgetHealth, rhs: WidgetHealth) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// Maps a Tile snapshot state to widget health.
public func widgetHealth(tile: TileSnapshotState, hasError: Bool) -> WidgetHealth {
    switch tile {
    case .failed:
        return .error
    case .setup, .choose:
        return .setup
    case .loading:
        return .stale
    case .empty:
        return .ok
    case .ready:
        return hasError ? .error : .ok
    }
}

/// Maps Beacon flags to widget health with precedence: error > needsSignIn > needsSettings > stale > ok.
public func widgetHealth(stale: Bool, error: Bool, needsSettings: Bool, needsSignIn: Bool) -> WidgetHealth {
    if error {
        return .error
    } else if needsSignIn {
        return .needsSignIn
    } else if needsSettings {
        return .setup
    } else if stale {
        return .stale
    } else {
        return .ok
    }
}

/// Returns the most urgent health status from an array, or `.ok` if empty.
public func mostUrgent(_ healths: [WidgetHealth]) -> WidgetHealth {
    healths.max() ?? .ok
}
