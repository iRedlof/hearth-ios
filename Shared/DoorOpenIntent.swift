import AppIntents
import HearthKit

/// Garage **Open** from the Doors widget — performed **in place**, no app launch (one tap, per the
/// user's choice; the widget is only reachable on an unlocked phone). `isDiscoverable = false`.
struct DoorOpenIntent: AppIntent {
    static var title: LocalizedStringResource { "Open garage" }
    static var isDiscoverable: Bool { false }
    /// Never from a locked phone. A widget can be reachable while the device is locked (Today View);
    /// the default policy would let this run there. Requiring authentication makes iOS ask for the
    /// device to be unlocked first; on an unlocked phone the tap runs as before.
    static var authenticationPolicy: IntentAuthenticationPolicy { .requiresAuthentication }

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
