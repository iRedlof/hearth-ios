import AppIntents
import WidgetKit
import HearthKit

/// Toggle a favourite from the widget (flip switch/light/fan/input_boolean, run a script), then
/// reload to verify against real HA state. Not gated.
struct FavToggleIntent: AppIntent {
    static var title: LocalizedStringResource { "Toggle favourite" }
    static var isDiscoverable: Bool { false }

    @Parameter(title: "Entity") var id: String
    @Parameter(title: "Turn on") var turnOn: Bool

    init() {}
    init(_ id: String, turnOn: Bool) { self.id = id; self.turnOn = turnOn }

    func perform() async throws -> some IntentResult {
        guard let config = HaConfigStore.load() else { return .result() }
        guard config.favouriteIds.contains(id) else { return .result() }
        let client = HaClient(config)
        let current = try favouriteFromState(await client.stateJson(id), id: id)
        guard current.available else { return .result() }
        try await client.callService(domain: current.domain,
                                     service: turnOn ? "turn_on" : "turn_off", entityId: id)
        WidgetCenter.shared.reloadTimelines(ofKind: "com.rohit.hearth.favourites")
        return .result()
    }
}
