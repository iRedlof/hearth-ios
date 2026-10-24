import SwiftUI
import WidgetKit
import LocalAuthentication
import HearthKit

/// A Disarm/Unlock request awaiting confirmation. Android gates these behind biometric/dialog;
/// on iOS the widget's gated intent brings the app forward and this gate runs Face ID — falling
/// back to a confirm dialog where no biometric/passcode is enrolled (same as Android's fallback).
enum GatedAlarmAction: String, Sendable {
    case disarm, unlock
    var domain: String { self == .disarm ? "alarm_control_panel" : "lock" }
    var service: String { self == .disarm ? "alarm_disarm" : "unlock" }
    func entityId(_ c: HaConfig) -> String { self == .disarm ? c.entityId : c.lockId }
    var reason: String { self == .disarm ? "Confirm to disarm the alarm" : "Confirm to unlock the door" }
    var title: String { self == .disarm ? "Disarm the alarm?" : "Unlock the door?" }
    var verb: String { self == .disarm ? "Disarm" : "Unlock" }
}

/// Shared singleton the gated AppIntent talks to once the app is foregrounded. Lives in the app
/// process (the intent uses `openAppWhenRun`); the view layer observes `confirming` to show the
/// dialog fallback.
@MainActor final class AlarmGate: ObservableObject {
    static let shared = AlarmGate()
    private init() {}

    /// Non-nil when a biometric isn't available and we need an on-screen Cancel/Confirm instead.
    @Published var confirming: GatedAlarmAction?

    /// Entry point from `AlarmGatedIntent.perform()` (running in-app after `openAppWhenRun`).
    /// Honours the configured confirm mode: biometric (Face ID / passcode) or a confirm dialog —
    /// and falls back to the dialog where no biometric/passcode is enrolled (bare Simulator).
    func request(_ action: GatedAlarmAction) {
        let useBiometric = HaConfigStore.load()?.confirmWithBiometric ?? true
        let ctx = LAContext()
        var error: NSError?
        if useBiometric, ctx.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) {
            ctx.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: action.reason) { [weak self] ok, _ in
                Task { @MainActor in if ok { await self?.perform(action) } }
            }
        } else {
            confirming = action   // dialog mode, or no biometric available
        }
    }

    func confirm(_ action: GatedAlarmAction) { confirming = nil; Task { await perform(action) } }
    func cancel() { confirming = nil }

    private func perform(_ action: GatedAlarmAction) async {
        guard let config = HaConfigStore.load() else { return }
        do {
            try await HaClient(config).callService(domain: action.domain, service: action.service,
                                                   entityId: action.entityId(config))
            WidgetCenter.shared.reloadAllTimelines()
        } catch {
            // No UI surface after auth; log so it isn't silent. The next widget refresh shows truth.
            print("Hearth: \(action.verb) failed — \(friendlyError(error))")
        }
    }
}
