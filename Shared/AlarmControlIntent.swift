import AppIntents
import WidgetKit
import HearthKit

/// Performs an Alarm widget action straight from a widget button — the iOS equivalent of
/// Android's Glance `actionRunCallback`: it runs in-process, no app launch.
///
/// Arm home / Arm away / Lock fire immediately (Android doesn't gate them). Disarm and Unlock
/// are `needsConfirm` actions; until the confirmation UX is wired they are intentionally **not**
/// performed here (a safe no-op) so a stray tap can't disarm a real home.
/// `isDiscoverable = false` keeps these out of Shortcuts — they're widget controls only.
struct AlarmControlIntent: AppIntent {
    static var title: LocalizedStringResource { "Alarm control" }
    static var isDiscoverable: Bool { false }

    @Parameter(title: "Action") var action: String

    init() {}
    init(_ action: String) { self.action = action }

    func perform() async throws -> some IntentResult {
        guard let config = HaConfigStore.load() else { return .result() }
        let client = HaClient(config)
        if let a = AlarmAction(rawValue: action), !a.needsConfirm {
            try await client.callService(domain: "alarm_control_panel", service: a.service, entityId: config.entityId)
        } else if let l = LockAction(rawValue: action), !l.needsConfirm {
            try await client.callService(domain: "lock", service: l.service, entityId: config.lockId)
        }
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}
