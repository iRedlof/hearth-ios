import AppIntents
import WidgetKit
import HearthKit

/// The ungated door actions — Close / Stop / Lock — in place (the "safe" set). Garage **Open** is
/// gated (see `DoorOpenIntent`). After acting it reloads so the row verifies against real HA state.
struct DoorActionIntent: AppIntent {
    static var title: LocalizedStringResource { "Door action" }
    static var isDiscoverable: Bool { false }

    @Parameter(title: "Entity") var id: String
    @Parameter(title: "Action") var action: String   // close | stop | lock (never "open")

    init() {}
    init(_ id: String, _ action: DoorAction) { self.id = id; self.action = action.rawValue }

    func perform() async throws -> some IntentResult {
        guard let config = HaConfigStore.load(),
              let act = DoorAction(rawValue: action), !act.needsConfirm else { return .result() }
        try await HaClient(config).callService(domain: act.service.domain, service: act.service.service, entityId: id)
        WidgetCenter.shared.reloadTimelines(ofKind: "com.rohit.hearth.doors")
        return .result()
    }
}
