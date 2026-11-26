import EventKit
import HearthKit

/// Thin wrapper around EventKit for calendar access
/// Note: This is app-side only, not tested in swift test (EventKit requires runtime permissions)
public final class CalendarAccess {
    private let store: EKEventStore

    public init() {
        self.store = EKEventStore()
    }

    /// Get current EventKit authorization status
    public func authorizationStatus() -> EKAuthorizationStatus {
        EKEventStore.authorizationStatus(for: .event)
    }

    /// Request full access to calendar events (iOS 17+)
    public func requestAccess() async -> Bool {
        do {
            return try await store.requestFullAccessToEvents()
        } catch {
            return false
        }
    }

    /// Fetch upcoming events within the specified number of days
    ///
    /// - Parameter days: Number of days from now to query
    /// - Returns: Array of LeaveByEvent objects mapped from EKEvent
    public func upcomingEvents(days: Int) async -> [LeaveByEvent] {
        let now = Date()
        let endDate = now.addingTimeInterval(Double(days) * 24 * 3600)

        let predicate = store.predicateForEvents(
            withStart: now,
            end: endDate,
            calendars: nil
        )

        let ekEvents = store.events(matching: predicate)

        return ekEvents.map { ekEvent in
            LeaveByEvent(
                title: ekEvent.title ?? "",
                startDate: ekEvent.startDate,
                endDate: ekEvent.endDate,
                location: ekEvent.location,
                isAllDay: ekEvent.isAllDay
            )
        }
    }
}
