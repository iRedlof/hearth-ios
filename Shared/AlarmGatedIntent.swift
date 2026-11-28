import AppIntents
import HearthKit

/// Disarm / Unlock from a widget button — performed **in place**, no app launch. The home-screen
/// widget is only reachable on an already-unlocked phone, so (per the user's choice) these run as a
/// single tap without a separate Face ID prompt. `isDiscoverable = false`: widget control only.
struct AlarmGatedIntent: AppIntent {
    static var title: LocalizedStringResource { "Alarm protected action" }
    static var isDiscoverable: Bool { false }
    /// Never from a locked phone. A widget can be reachable while the device is locked (Today View);
    /// the default policy would let this run there. Requiring authentication makes iOS ask for the
    /// device to be unlocked first; on an unlocked phone the tap runs as before.
    static var authenticationPolicy: IntentAuthenticationPolicy { .requiresAuthentication }

    @Parameter(title: "Action") var action: String
    @Parameter(title: "Account scope") var scope: String
    @Parameter(title: "Alarm revision") var revision: String
    @Parameter(title: "Entity") var entityID: String

    init() {}
    init(_ action: String, snapshot: AlarmSnapshot, entityID: String) {
        self.action = action; self.scope = snapshot.requestScope
        self.revision = snapshot.alarmRevision; self.entityID = entityID
    }

    func perform() async throws -> some IntentResult {
        guard ["disarm", "unlock"].contains(action) else { return .result() }
        try await AlarmActionRuntime.perform(scope: scope, revision: revision, entityID: entityID, action: action)
        return .result()
    }
}
