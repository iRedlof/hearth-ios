import Foundation

/// ChargePoint alert categorization and edit-key mapping for the Alerts settings page.

public enum CpAlertKind: Sendable, Equatable {
    case yourTurn, acceptedHeld, snoozed, secondOffer
}

/// Returns the edit-key string for a given alert kind, matching the existing
/// CpSettingsSection edit names and CpAlertPreference raw values.
public func cpAlertEditKey(_ alert: CpAlertKind) -> String {
    switch alert {
    case .yourTurn: return "offer"
    case .acceptedHeld: return "accepted"
    case .snoozed: return "snoozed"
    case .secondOffer: return "second"
    }
}

/// Whether the "While Auto runs" alert group is enabled (requires Auto to be ON).
public func whileAutoRunsEnabled(autoOn: Bool) -> Bool {
    autoOn
}
