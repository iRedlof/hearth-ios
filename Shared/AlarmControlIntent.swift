import AppIntents
import HearthKit

/// Performs an Alarm widget action straight from a widget button — the iOS equivalent of
/// Android's Glance `actionRunCallback`: it runs in-process, no app launch.
///
/// Arm home / Arm away / Lock use the origin rendered on their card.
/// `isDiscoverable = false` keeps these out of Shortcuts — they're widget controls only.
struct AlarmControlIntent: AppIntent {
    static var title: LocalizedStringResource { "Alarm control" }
    static var isDiscoverable: Bool { false }

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
        guard ["armHome", "armAway", "lock"].contains(action) else { return .result() }
        try await AlarmActionRuntime.perform(scope: scope, revision: revision, entityID: entityID, action: action)
        return .result()
    }
}
