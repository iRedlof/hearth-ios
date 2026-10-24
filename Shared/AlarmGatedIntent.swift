import AppIntents
import HearthKit

/// Disarm / Unlock from a widget button. These are protected actions: `openAppWhenRun` brings
/// Hearth to the foreground, then `AlarmGate` runs Face ID (or a confirm dialog) before performing
/// — the iOS parity for Android's biometric/dialog gate. `isDiscoverable = false`: widget only.
struct AlarmGatedIntent: AppIntent {
    static var title: LocalizedStringResource { "Confirm alarm action" }
    static var isDiscoverable: Bool { false }
    static var openAppWhenRun: Bool { true }

    @Parameter(title: "Action") var action: String

    init() {}
    init(_ action: GatedAlarmAction) { self.action = action.rawValue }

    @MainActor
    func perform() async throws -> some IntentResult {
        if let a = GatedAlarmAction(rawValue: action) { AlarmGate.shared.request(a) }
        return .result()
    }
}
