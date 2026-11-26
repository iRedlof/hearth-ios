import Foundation
import UserNotifications
import HearthKit
import os.log

/// Notifications for house events (leave-by checks and travel trips).
///
/// Uses calendar triggers to schedule at a specific date/time. Reuses the stable ids from
/// `plannedNotifications` so rescheduling replaces rather than duplicates.
enum HouseNotify {
    private static let logger = Logger(subsystem: "com.rohit.hearth", category: "HouseNotify")
    /// Check the current notification authorization status
    static func authorizationStatus() async -> UNAuthorizationStatus {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        return settings.authorizationStatus
    }

    /// Request notification permission from the user
    ///
    /// - Returns: true if granted, false if denied
    static func requestPermission() async -> Bool {
        do {
            return try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
        } catch {
            return false
        }
    }

    /// Schedule the given planned notifications using calendar triggers
    ///
    /// Each notification is scheduled at its `fireAt` date. If a notification with the same id
    /// already exists, it will be replaced (UNUserNotificationCenter automatically replaces
    /// requests with matching identifiers).
    ///
    /// - Parameter planned: Notifications to schedule
    static func schedule(_ planned: [PlannedNotification]) {
        let center = UNUserNotificationCenter.current()

        for notification in planned {
            let content = UNMutableNotificationContent()
            content.title = notification.title
            content.body = notification.body
            content.sound = .default

            // Create a calendar trigger for the fireAt date
            let components = Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute, .second],
                from: notification.fireAt
            )
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)

            let request = UNNotificationRequest(
                identifier: notification.id,
                content: content,
                trigger: trigger
            )

            center.add(request) { error in
                if let error = error {
                    logger.error("Failed to schedule notification \(notification.id, privacy: .public): \(error)")
                }
            }
        }
    }

    /// Cancel notifications with the given ids
    ///
    /// - Parameter ids: Notification identifiers to cancel
    static func cancel(ids: [String]) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ids)
    }

    /// Cancel all notifications matching a prefix
    ///
    /// Useful for clearing all leaveby- or travel- notifications before rescheduling.
    ///
    /// - Parameter prefix: ID prefix to match (e.g., "leaveby-", "travel-")
    static func cancelAll(prefix: String) async {
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests()
        let matching = pending
            .filter { $0.identifier.hasPrefix(prefix) }
            .map { $0.identifier }
        cancel(ids: matching)
    }

    /// Post an immediate notification for safety alerts
    ///
    /// Used for critical failures (lock won't lock, alarm won't arm) that need immediate attention.
    ///
    /// - Parameters:
    ///   - id: Unique identifier for the notification
    ///   - title: Notification title
    ///   - body: Notification body
    static func postImmediate(id: String, title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: id,
            content: content,
            trigger: nil  // nil trigger = immediate delivery
        )

        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                logger.error("Failed to post immediate notification \(id, privacy: .public): \(error)")
            }
        }
    }
}
