import AppIntents
import WidgetKit
import HearthKit

/// ChargePoint widget controls. `autoToggle` arms / pauses the auto-waitlist run (the `cpAutoDecide`
/// engine then acts on the next refresh); `refresh` re-reads now. Manual accept/snooze/stop are
/// handled automatically by the auto engine or via "Open" to the ChargePoint app (the reduced card
/// exposes a single action; the rich per-state key row is a documented follow-up).
struct CpControlIntent: AppIntent {
    static var title: LocalizedStringResource { "ChargePoint" }
    static var isDiscoverable: Bool { false }

    @Parameter(title: "Action") var action: String   // "autoToggle" | "refresh"

    init() {}
    init(_ action: String) { self.action = action }

    func perform() async throws -> some IntentResult {
        if action == "autoToggle" {
            let run = CpSessionStore.loadRun()
            let arming = !run.armed
            let next = arming
                ? cpResumeRun(run, nil, Int64(Date().timeIntervalSince1970 * 1000))
                : cpPauseRun(run)
            CpSessionStore.saveRun(next)
            if arming { CpNotify.requestPermission() }   // ask only when the auto-engine is turned on
        }
        WidgetCenter.shared.reloadTimelines(ofKind: "com.rohit.hearth.chargepoint")
        return .result()
    }
}
