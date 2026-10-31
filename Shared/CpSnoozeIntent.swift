import AppIntents
import WidgetKit
import HearthKit

/// Snooze the ChargePoint offer **in place** (no app launch) for the standard hour the auto-engine
/// uses. (The length picker used to open the app; one tap is the widget-native behaviour.)
struct CpSnoozeIntent: AppIntent {
    static var title: LocalizedStringResource { "Snooze ChargePoint offer" }
    static var isDiscoverable: Bool { false }
    @Parameter(title: "Rendered origin", default: "") var origin: String

    init() {}
    init(origin: String) { self.origin = origin }

    @MainActor
    func perform() async throws -> some IntentResult {
        await CpWidgetOperation.perform("snooze", origin: origin)
        return .result()
    }
}
