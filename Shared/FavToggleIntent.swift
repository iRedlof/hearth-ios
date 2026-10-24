import AppIntents
import WidgetKit
import HearthKit

/// Toggle a favourite from the widget (flip switch/light/fan/input_boolean, run a script), then
/// reload to verify against real HA state. Not gated.
struct FavToggleIntent: AppIntent {
    static var title: LocalizedStringResource { "Toggle favourite" }
    static var isDiscoverable: Bool { false }

    @Parameter(title: "Entity") var id: String
    @Parameter(title: "On") var on: Bool

    init() {}
    init(_ id: String, on: Bool) { self.id = id; self.on = on }

    func perform() async throws -> some IntentResult {
        guard let config = HaConfigStore.load() else { return .result() }
        let call = favServiceFor(id, on: on)
        try await HaClient(config).callService(domain: call.domain, service: call.service, entityId: id)
        WidgetCenter.shared.reloadTimelines(ofKind: "com.rohit.hearth.favourites")
        return .result()
    }
}
