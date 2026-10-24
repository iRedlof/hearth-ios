import AppIntents
import HearthKit

/// Snooze from the card with a length choice. `openAppWhenRun` brings Hearth forward so `CpSnoozeGate`
/// can offer 10 / 30 / 60 minutes (matching Android) before calling snooze.
struct CpSnoozeIntent: AppIntent {
    static var title: LocalizedStringResource { "Snooze ChargePoint offer" }
    static var isDiscoverable: Bool { false }
    static var openAppWhenRun: Bool { true }

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult {
        CpSnoozeGate.shared.request()
        return .result()
    }
}
