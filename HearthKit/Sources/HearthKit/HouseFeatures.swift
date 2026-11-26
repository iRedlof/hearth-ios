import Foundation

/// Formatting helpers for house features (leave-by, travel, safety)
/// These are pure functions to enable testing without UI/permissions.

/// Format the subtitle for the next upcoming trip
///
/// - Parameters:
///   - trips: Sorted trips (by startDate ascending)
///   - now: Current time
/// - Returns: Formatted subtitle like "Next: Lisbon trip · Sat" or "No trips in the next 7 days"
public func nextTripSubtitle(trips: [Trip], now: Date) -> String {
    guard let first = trips.first else {
        return "No trips in the next 7 days"
    }

    // Format day of week (e.g., "Sat")
    let dayFormatter = Date.FormatStyle()
        .weekday(.abbreviated)
    let day = first.startDate.formatted(dayFormatter)

    return "Next: \(first.title) · \(day)"
}

/// State for calendar permission banner
public enum CalendarBannerState: Sendable, Equatable {
    case hidden
    case needsPermission
}

/// State for notification permission banner
public enum NotificationBannerState: Sendable, Equatable {
    case hidden
    case needsPermission
}

/// Determine if the calendar permission banner should be shown
///
/// - Parameters:
///   - enabled: Whether the feature is enabled
///   - hasCalendarAccess: Whether calendar access is authorized
/// - Returns: Banner state
public func calendarBannerState(enabled: Bool, hasCalendarAccess: Bool) -> CalendarBannerState {
    guard enabled else { return .hidden }
    return hasCalendarAccess ? .hidden : .needsPermission
}

/// Determine if the notification permission banner should be shown
///
/// - Parameters:
///   - enabled: Whether the feature is enabled
///   - hasNotificationAccess: Whether notification access is authorized
/// - Returns: Banner state
public func notificationBannerState(enabled: Bool, hasNotificationAccess: Bool) -> NotificationBannerState {
    guard enabled else { return .hidden }
    return hasNotificationAccess ? .hidden : .needsPermission
}
