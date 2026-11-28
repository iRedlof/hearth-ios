import AppIntents
import WidgetKit
import HearthKit

/// Runs Goodnight automation from the lock screen, gated by the time window.
/// If Goodnight is disabled or the current time is outside the window, nothing happens.
struct RunGoodnightIntent: AppIntent {
    static var title: LocalizedStringResource { "Run Goodnight" }
    static var openAppWhenRun: Bool { false }

    func perform() async throws -> some IntentResult {
        // Load Goodnight configuration
        let config = GoodnightStore.load()

        // If Goodnight is disabled, do nothing
        guard config.enabled else {
            return .result(dialog: "Goodnight is disabled.")
        }

        // Load Home Assistant configuration
        guard let haConfig = HaConfigStore.load() else {
            return .result(dialog: "Home Assistant is not configured.")
        }

        // Check if Goodnight is currently active
        let now = Date()
        var calendar = Calendar.current
        calendar.timeZone = .current

        guard goodnightActive(now: now, startHour: config.startHour, endHour: config.endHour, calendar: calendar) else {
            // Format the time window for the dialog
            let startTime = formatHour(config.startHour)
            let endTime = formatHour(config.endHour)
            return .result(dialog: "Goodnight runs only from \(startTime) to \(endTime).")
        }

        // Execute Goodnight automation
        let result = await GoodnightRuntime.run(config: config, haConfig: haConfig, now: now)

        // Reload widgets to reflect the new state
        WidgetCenter.shared.reloadAllTimelines()

        // Build a summary of what happened
        var summary: [String] = []
        if !result.garagesClosed {
            summary.append("garages")
        }
        if !result.lightsOff {
            summary.append("lights")
        }
        if !result.locked {
            summary.append("lock")
        }
        if !result.armed {
            summary.append("alarm")
        }

        if summary.isEmpty {
            return .result(dialog: "Goodnight completed successfully.")
        } else {
            return .result(dialog: "Goodnight completed with errors: \(summary.joined(separator: ", ")).")
        }
    }

    /// Formats an hour (0–23) as a short, locale-aware time (e.g., "9:00 PM").
    private func formatHour(_ hour: Int) -> String {
        let date = Calendar.current.date(bySettingHour: hour, minute: 0, second: 0, of: Date()) ?? Date()
        return HearthTimeFormatter.shortTime(date)
    }
}
