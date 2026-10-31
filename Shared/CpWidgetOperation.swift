import Foundation
import WidgetKit
import HearthKit

@MainActor enum CpWidgetOperation {
    static func perform(_ name: String, origin encoded: String) async {
        guard let origin = CpSessionStore.actionOrigin(encoded),
              let action = CpOwnedAction(rawValue: name == "rejoin" ? "unsnooze" : name), action != .legacy else { return }
        _ = try? await CpSessionStore.runtime().perform(origin: origin, action: action)
        reload()
    }

    static func setAuto(_ desired: String, origin encoded: String) async {
        guard let origin = CpSessionStore.actionOrigin(encoded), let desired = CpDesiredAutoAction(rawValue: desired) else { return }
        if let result = try? await CpSessionStore.runtime().setAuto(origin: origin, desired: desired),
           let mode = result.activatedMode {
            _ = try? CpSessionStore.repository().store.withChosenMode(expected: mode) { CpSessionStore.requestOwnedNotificationPermission() }
        }
        reload()
    }

    static func reload() {
        if CpSessionStore.fixtureReloadHandled() { return }
        WidgetCenter.shared.reloadTimelines(ofKind: "com.rohit.hearth.chargepoint")
        RefreshSignal.shared.bump()
    }
}
