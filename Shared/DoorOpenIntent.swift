import AppIntents
import HearthKit

/// Garage **Open** from the Doors widget — performed **in place**, no app launch (one tap, per the
/// user's choice; the widget is only reachable on an unlocked phone). `isDiscoverable = false`.
struct DoorOpenIntent: AppIntent {
    static var title: LocalizedStringResource { "Open garage" }
    static var isDiscoverable: Bool { false }

    @Parameter(title: "Entity") var id: String
    @Parameter(title: "Account scope") var scope: String
    @Parameter(title: "Door selection") var revision: String

    init() {}
    init(scope: String, revision: String, id: String) {
        self.scope = scope; self.revision = revision; self.id = id
    }

    func perform() async throws -> some IntentResult {
        try await DoorActionRuntime.perform(scope: scope, revision: revision, entityID: id, action: "open")
        return .result()
    }
}
