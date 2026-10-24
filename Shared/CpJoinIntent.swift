import AppIntents
import HearthKit

/// Join the ChargePoint waitlist from the card. `openAppWhenRun` brings Hearth forward so `CpJoinGate`
/// can ask "Join & auto-run" vs "Just join" (matching Android's join sheet) before joining.
struct CpJoinIntent: AppIntent {
    static var title: LocalizedStringResource { "Join ChargePoint waitlist" }
    static var isDiscoverable: Bool { false }
    static var openAppWhenRun: Bool { true }

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult {
        CpJoinGate.shared.request()
        return .result()
    }
}
