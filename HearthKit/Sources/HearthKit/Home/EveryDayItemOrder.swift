import Foundation

/// Defines the canonical display order for every-day items on the iOS Home dashboard.
/// This order matches the approved Android v2 mocks.
public enum EveryDayItem: String, Sendable, CaseIterable {
    case goodnight
    case routines
    case leaveBy
    case travelDays
    case safetyAlerts

    /// The canonical display order for every-day items.
    public static let displayOrder: [EveryDayItem] = [
        .goodnight,
        .routines,
        .leaveBy,
        .travelDays,
        .safetyAlerts,
    ]
}
