import AppIntents
import WidgetKit
import HearthKit

/// Run a script from the Quick widget (`script.turn_on`), then reload. Not gated (running a scene/
/// routine is the "safe" set on Android's home screen).
struct QuickRunIntent: AppIntent {
    static var title: LocalizedStringResource { "Run script" }
    static var isDiscoverable: Bool { false }

    @Parameter(title: "Script") var id: String

    init() {}
    init(_ id: String) { self.id = id }

    func perform() async throws -> some IntentResult {
        guard let config = HaConfigStore.load() else { return .result() }
        try await HaClient(config).callService(domain: "script", service: "turn_on", entityId: id)
        WidgetCenter.shared.reloadTimelines(ofKind: "com.rohit.hearth.quick")
        return .result()
    }
}
