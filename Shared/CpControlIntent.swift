import AppIntents
import WidgetKit
import HearthKit

/// Explicit Auto control: idle joins and arms; queued resumes; turning off preserves run history.
struct CpControlIntent: AppIntent {
    static var title: LocalizedStringResource { "ChargePoint" }
    static var isDiscoverable: Bool { false }

    @Parameter(title: "Action") var action: String   // "autoToggle" | "refresh"

    init() {}
    init(_ action: String) { self.action = action }

    @MainActor func perform() async throws -> some IntentResult {
        if action == "autoToggle" {
            let run = CpSessionStore.loadRun()
            let arming = !run.armed
            if arming {
                await CpWidgetOperation.enableAuto()
                if CpSessionStore.loadRun().armed { CpNotify.requestPermission() }
            } else {
                CpSessionStore.saveRun(cpPauseRun(run))
            }
        }
        CpWidgetOperation.reload()
        return .result()
    }
}
