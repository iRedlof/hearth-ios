import Foundation

/// An event that may require leave-by checks
public struct LeaveByEvent: Sendable, Equatable {
    public let title: String
    public let startDate: Date
    public let endDate: Date
    public let location: String?
    public let isAllDay: Bool

    public init(
        title: String,
        startDate: Date,
        endDate: Date? = nil,
        location: String?,
        isAllDay: Bool = false
    ) {
        self.title = title
        self.startDate = startDate
        self.endDate = endDate ?? startDate.addingTimeInterval(3600) // Default to 1 hour duration
        self.location = location
        self.isAllDay = isAllDay
    }
}

/// A house check to perform before leaving
public enum LeaveByItem: Sendable, Equatable {
    case alarm
    case lock
    case thermostat
}

/// A scheduled leave-by check for an event
public struct LeaveByCheck: Sendable, Equatable {
    public let eventTitle: String
    public let notifyAt: Date
    public let items: [LeaveByItem]

    public init(eventTitle: String, notifyAt: Date, items: [LeaveByItem]) {
        self.eventTitle = eventTitle
        self.notifyAt = notifyAt
        self.items = items
    }
}

/// Compute leave-by checks for upcoming events with locations
///
/// - Parameters:
///   - events: Calendar events to check
///   - minutesBefore: How many minutes before the event to notify
///   - now: Current time (for filtering)
///   - hasAlarm: Whether an alarm system is configured
///   - hasLock: Whether a lock is configured
///   - hasClimate: Whether climate control is configured
/// - Returns: Checks sorted by notifyAt ascending
public func leaveByChecks(
    events: [LeaveByEvent],
    minutesBefore: Int,
    now: Date,
    hasAlarm: Bool,
    hasLock: Bool,
    hasClimate: Bool
) -> [LeaveByCheck] {
    // Build the list of configured items in stable order
    var items: [LeaveByItem] = []
    if hasAlarm { items.append(.alarm) }
    if hasLock { items.append(.lock) }
    if hasClimate { items.append(.thermostat) }

    // If no items configured, no checks can be produced
    guard !items.isEmpty else {
        return []
    }

    // Filter and map events to checks
    let checks = events.compactMap { event -> LeaveByCheck? in
        // Exclude events without a non-empty location
        guard let location = event.location, !location.isEmpty else {
            return nil
        }

        // Exclude events that have already started
        guard event.startDate > now else {
            return nil
        }

        // Compute notifyAt by subtracting minutesBefore from startDate
        let notifyAt = Date(timeIntervalSince1970: event.startDate.timeIntervalSince1970 - Double(minutesBefore * 60))

        // Exclude if notifyAt is in the past (but include if it's exactly now)
        guard notifyAt >= now else {
            return nil
        }

        return LeaveByCheck(
            eventTitle: event.title,
            notifyAt: notifyAt,
            items: items
        )
    }

    // Sort by notifyAt ascending
    return checks.sorted { $0.notifyAt < $1.notifyAt }
}
