import AppIntents
import WidgetKit
import HearthKit

/// Disarm / Unlock from a widget button — performed **in place**, no app launch. The home-screen
/// widget is only reachable on an already-unlocked phone, so (per the user's choice) these run as a
/// single tap without a separate Face ID prompt. `isDiscoverable = false`: widget control only.
struct AlarmGatedIntent: AppIntent {
    static var title: LocalizedStringResource { "Alarm protected action" }
    static var isDiscoverable: Bool { false }

    @Parameter(title: "Action") var action: String

    init() {}
    init(_ action: GatedAlarmAction) { self.action = action.rawValue }

    func perform() async throws -> some IntentResult {
        guard let config = HaConfigStore.load(), let a = GatedAlarmAction(rawValue: action) else { return .result() }
        try await HaClient(config).callService(domain: a.domain, service: a.service, entityId: a.entityId(config))
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}
