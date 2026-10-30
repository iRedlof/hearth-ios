import AppIntents
import WidgetKit
import HearthKit

/// The header "Check again" button — re-reads the widget from Home Assistant now, like Android's
/// refresh glyph. Reloading the timeline re-runs the provider's live fetch; the "Checked <time>"
/// stamp updates when the fresh read returns. `isDiscoverable = false`: a widget control, not a Shortcut.
struct WidgetRefreshIntent: AppIntent {
    static var title: LocalizedStringResource { "Refresh" }
    static var isDiscoverable: Bool { false }

    @Parameter(title: "Widget kind") var kind: String

    init() {}
    init(_ kind: String) { self.kind = kind }

    @MainActor
    func perform() async throws -> some IntentResult {
        if kind == "com.rohit.hearth.chargepoint", let operation = CpSessionStore.loadOperation(),
           operation.error != nil || Date().timeIntervalSince(operation.startedAt) >= 120 {
            CpSessionStore.saveOperation(nil)
        }
        if kind.isEmpty {
            WidgetCenter.shared.reloadAllTimelines()
        } else {
            WidgetCenter.shared.reloadTimelines(ofKind: kind)
        }
        RefreshSignal.shared.bump()   // so the in-app Live view re-fetches when the glyph is tapped there
        return .result()
    }
}
