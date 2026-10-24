import Foundation
import UserNotifications

/// Local notifications for the ChargePoint auto-engine. On Android an exact alarm wakes the device
/// to act silently; iOS can't, so the auto-engine's "drive now" becomes a user-visible prompt.
enum CpNotify {
    static func requestPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    static func driveNow() {
        let content = UNMutableNotificationContent()
        content.title = "Drive now"
        content.body = "Your ChargePoint spot is held — plug in before it passes."
        content.sound = .default
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: "cp.driveNow", content: content, trigger: nil))
    }
}
