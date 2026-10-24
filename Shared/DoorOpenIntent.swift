import AppIntents
import WidgetKit
import HearthKit

/// Garage **Open** from the Doors widget — performed **in place**, no app launch (one tap, per the
/// user's choice; the widget is only reachable on an unlocked phone). `isDiscoverable = false`.
struct DoorOpenIntent: AppIntent {
    static var title: LocalizedStringResource { "Open garage" }
    static var isDiscoverable: Bool { false }

    @Parameter(title: "Entity") var id: String

    init() {}
    init(_ id: String) { self.id = id }

    func perform() async throws -> some IntentResult {
        guard let config = HaConfigStore.load() else { return .result() }
        try await HaClient(config).callService(domain: "cover", service: "open_cover", entityId: id)
        WidgetCenter.shared.reloadTimelines(ofKind: "com.rohit.hearth.doors")
        return .result()
    }
}
