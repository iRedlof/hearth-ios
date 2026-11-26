import AppIntents
import WidgetKit
import HearthKit

/// Explicit Auto control: idle joins and arms; queued resumes; turning off preserves run history.
struct CpControlIntent: AppIntent {
    static var title: LocalizedStringResource { "ChargePoint" }
    static var isDiscoverable: Bool { false }

    @Parameter(title: "Desired mode") var action: String
    @Parameter(title: "Rendered origin", default: "") var origin: String

    init() {}
    init(_ action: String, origin: String) { self.action = action; self.origin = origin }

    @MainActor func perform() async throws -> some IntentResult {
        await CpWidgetOperation.setAuto(action, origin: origin)
        return .result()
    }
}
