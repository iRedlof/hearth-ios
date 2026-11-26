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
    @Parameter(title: "Thermostat selection") var thermostatOrigin: String

    init() { kind = ""; thermostatOrigin = "" }
    init(_ kind: String, thermostatOrigin: String = "") { self.kind = kind; self.thermostatOrigin = thermostatOrigin }

    @MainActor
    func perform() async throws -> some IntentResult {
        if kind == "com.rohit.hearth.chargepoint", CpSessionStore.fixtureReloadHandled() { return .result() }
        if kind == "com.rohit.hearth.thermostat" {
            guard let origin = HearthKit.thermostatOrigin(from: thermostatOrigin),
                  let context = HaConfigStore.context(), origin.matches(context) else { return .result() }
            WidgetCenter.shared.reloadTimelines(ofKind: kind)
            RefreshSignal.shared.requestThermostatRefresh(ThermostatRefreshRequest(selection: origin))
            return .result()
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
