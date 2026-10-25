import Foundation

/// Map the core ChargePoint state onto the display snapshot. `email` is the signed-in account (its
/// local part is shown); pass nil when unknown.
public func cpSnapshot(_ state: CpState, email: String?, checkedAt: String) -> CpSnapshot {
    let ans = cpAnswer(state)
    let account: String
    if state.signedOut {
        account = "Signed out"
    } else if let local = email?.trimmingCharacters(in: .whitespaces).split(separator: "@").first.map(String.init),
              !local.isEmpty {
        account = local
    } else {
        account = "Account unknown"
    }
    let showPlugs = !state.signedOut && state.location != nil && state.charging == nil
    let plugsFree = (showPlugs ? state.now : nil).map { "\($0.free) of \($0.total) free" }
    // "Go to" the assigned charger when offered/held; per-level floor stats when idle with a location.
    var goTo: String? = nil
    if case let .inLine(_, s, _, offer?, _) = state.waitlist,
       ["ACCEPT_PENDING", "PENDING_PLUG_IN", "DIB_PENDING_PLUG_IN"].contains(s), !offer.charger.isEmpty {
        goTo = offer.charger
    }
    var isIdle = false
    if case .notQueued = state.waitlist { isIdle = showPlugs }
    return CpSnapshot(
        site: state.location?.title ?? "ChargePoint",
        account: account,
        bigAnswer: ans.big,
        unit: ans.unit,
        sub: ans.sub,
        plugsFree: plugsFree,
        autoOn: state.autoOn,
        actionLabel: ans.action,
        keys: cpManualKeys(state),
        deadline: cpDeadline(state),
        goTo: goTo,
        floors: isIdle ? state.floors : [],
        tone: .orange)
}
