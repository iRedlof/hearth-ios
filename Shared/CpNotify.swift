import Foundation
import UserNotifications

/// Local notifications for the ChargePoint auto-engine. On Android an exact alarm wakes the device to
/// act silently; iOS can't, so the engine runs best-effort on refresh and surfaces these prompts. The
/// title/body/id come from `cpAlertContent`; whether to post at all is decided by `cpAlertAllowed`.
enum CpNotify {
    static func requestPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    static func post(title: String, body: String, id: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: id, content: content, trigger: nil))
    }
}
