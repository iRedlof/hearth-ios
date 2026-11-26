import Foundation

/// A trip requiring travel-day notification
public struct Trip: Sendable, Equatable {
    public let title: String
    public let startDate: Date
    public let notifyAt: Date

    public init(title: String, startDate: Date, notifyAt: Date) {
        self.title = title
        self.startDate = startDate
        self.notifyAt = notifyAt
    }
}

/// Compute travel-day notifications for upcoming trips
///
/// A trip is defined as an all-day event OR an event lasting 24+ hours.
/// Trips starting within the next 7 days get a notification at 8 PM the day before.
///
/// - Parameters:
///   - events: Calendar events to check
///   - now: Current time (for filtering)
///   - calendar: Calendar instance with the desired timezone for 8 PM calculation
/// - Returns: Trips sorted by startDate ascending
public func travelTrips(
    events: [LeaveByEvent],
    now: Date,
    calendar: Calendar
) -> [Trip] {
    let sevenDaysFromNow = now.addingTimeInterval(7 * 24 * 3600)

    let trips = events.compactMap { event -> Trip? in
        // Check if it's a trip: all-day OR duration >= 24 hours
        let duration = event.endDate.timeIntervalSince(event.startDate)
        let isTrip = event.isAllDay || duration >= 24 * 3600

        guard isTrip else {
            return nil
        }

        // Must start within next 7 days
        guard event.startDate > now && event.startDate <= sevenDaysFromNow else {
            return nil
        }

        // Compute notifyAt: 8 PM (20:00) on the day before startDate
        let dayBefore = calendar.date(byAdding: .day, value: -1, to: event.startDate)!
        guard let notifyAt = calendar.date(bySettingHour: 20, minute: 0, second: 0, of: dayBefore) else {
            return nil
        }

        // Exclude if notifyAt is in the past
        guard notifyAt > now else {
            return nil
        }

        return Trip(
            title: event.title,
            startDate: event.startDate,
            notifyAt: notifyAt
        )
    }

    // Sort by startDate ascending
    return trips.sorted { $0.startDate < $1.startDate }
}
