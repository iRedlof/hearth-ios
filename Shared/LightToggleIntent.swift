import AppIntents
import WidgetKit
import HearthKit

/// Toggle a light straight from the widget tile (`light.turn_on` / `turn_off`), then reload so the
/// tile verifies against real HA state (never fakes success). Lights aren't gated.
struct LightToggleIntent: AppIntent {
    static var title: LocalizedStringResource { "Toggle light" }
    static var isDiscoverable: Bool { false }

    @Parameter(title: "Light") var id: String
    @Parameter(title: "Turn on") var turnOn: Bool

    init() {}
    init(_ id: String, on turnOn: Bool) { self.id = id; self.turnOn = turnOn }

    func perform() async throws -> some IntentResult {
        guard let config = HaConfigStore.load() else { return .result() }
        try await HaClient(config).callService(domain: "light", service: turnOn ? "turn_on" : "turn_off", entityId: id)
        WidgetCenter.shared.reloadTimelines(ofKind: "com.rohit.hearth.lights")
        return .result()
    }
}
