import Foundation
import EventKit
import HearthKit

/// Coordinator that scans the calendar and schedules house notifications (leave-by and travel)
/// on app launch or foreground entry.
///
/// Only runs when at least one house feature (leave-by or travel) is enabled AND calendar access
/// is authorized. Cancels stale notifications before rescheduling to avoid duplicates.
enum HouseScheduler {
    /// Scan the calendar and reschedule house notifications if features are enabled and authorized.
    ///
    /// This should be called on app launch and when the app enters the foreground. It captures
    /// the current date once and runs asynchronously without blocking the caller.
    static func refreshScheduleIfNeeded() {
        let now = Date()

        Task {
            await performRefresh(now: now)
        }
    }

    private static func performRefresh(now: Date) async {
        // Check if any house features are enabled
        let leaveByOn = HouseFeaturesStore.leaveByEnabled
        let travelOn = HouseFeaturesStore.travelEnabled

        guard leaveByOn || travelOn else {
            // No features enabled → cancel all house notifications
            await cancelHouseNotifications()
            return
        }

        // Check calendar authorization
        let calendarAccess = CalendarAccess()
        let authStatus = calendarAccess.authorizationStatus()

        guard authStatus == .fullAccess || authStatus == .authorized else {
            // Not authorized → cancel all house notifications
            await cancelHouseNotifications()
            return
        }

        // Fetch upcoming events (7 days)
        let events = await calendarAccess.upcomingEvents(days: 7)

        // Load HaConfig to check which items are configured
        let config = HaConfigStore.load()
        let hasAlarm = !(config?.entityId.isEmpty ?? true)
        let hasLock = !(config?.lockId.isEmpty ?? true)
        let hasClimate = !(config?.climateId.isEmpty ?? true)

        // Compute leave-by checks if enabled
        let checks: [LeaveByCheck]
        if leaveByOn {
            let minutesBefore = HouseFeaturesStore.leaveByMinutes
            checks = leaveByChecks(
                events: events,
                minutesBefore: minutesBefore,
                now: now,
                hasAlarm: hasAlarm,
                hasLock: hasLock,
                hasClimate: hasClimate
            )
        } else {
            checks = []
        }

        // Compute travel trips if enabled
        let trips: [Trip]
        if travelOn {
            var calendar = Calendar.current
            calendar.timeZone = .current
            trips = travelTrips(events: events, now: now, calendar: calendar)
        } else {
            trips = []
        }

        // Build planned notifications
        let planned = plannedNotifications(leaveBy: checks, travel: trips)

        // Cancel stale notifications before scheduling new ones
        await cancelHouseNotifications()

        // Schedule the new notifications
        HouseNotify.schedule(planned)
    }

    /// Cancel all leave-by and travel notifications
    private static func cancelHouseNotifications() async {
        await HouseNotify.cancelAll(prefix: "leaveby-")
        await HouseNotify.cancelAll(prefix: "travel-")
    }
}
