import Foundation

/// Map the core ChargePoint state onto the display snapshot. `email` is the signed-in account (its
/// local part is shown); pass nil when unknown.
public func cpSnapshot(_ state: CpState, email: String?, checkedAt: String, now: Date = Date()) -> CpSnapshot {
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
    var status = ""
    var offer: CpOffer?
    if case let .inLine(_, value, _, assignment, _) = state.waitlist { status = value; offer = assignment }
    let charging = state.charging != nil || status == "CHARGING"
    let configured = !state.signedOut && !state.account.needsReauth && state.location != nil
    let idle = status.isEmpty || status == "UNKNOWN"
    let showPlugs = configured && !charging && idle
    let plugsFree = (showPlugs ? state.now : nil).map { "\($0.free) of \($0.total) free" }
    let assigned = ["ACCEPT_PENDING", "PENDING_PLUG_IN", "DIB_PENDING_PLUG_IN", "CHARGING_FAULT",
                    "DIB_PLUG_OUT", "PENDING_PLUG_OUT", "OVER_STAYED", "BLOCKED"].contains(status)
    let goTo = configured && assigned ? offer?.charger.nilIfEmpty : nil
    let deadline = configured ? cpDeadline(state) : nil
    let expired = deadline.map { $0 <= now } ?? false
    var sub = ans.sub
    var unit = ans.unit
    if configured {
        if status == "ACCEPT_PENDING" { unit = "to accept" }
        if CP_HELD.contains(status) { unit = "to plug in" }
    }
    if let deadline {
        if status == "ACCEPT_PENDING" { sub = "Respond by \(cpClockString(deadline))" }
        if ["PENDING_PLUG_IN", "DIB_PENDING_PLUG_IN"].contains(status) {
            sub = "Plug in by \(cpClockString(deadline))"
        }
        if status == "PASS" { sub = "Back in line at \(cpClockString(deadline))" }
        if ["PENDING_PLUG_OUT", "OVER_STAYED"].contains(status) { sub = "Move by \(cpClockString(deadline))" }
    } else if configured && (status == "ACCEPT_PENDING" || CP_HELD.contains(status)) {
        sub = "Deadline unknown"
    }
    if expired { sub = "Time elapsed · Refresh to check" }
    let freeDetail = showPlugs ? state.now.map {
        ["of \($0.total) plugs", "\($0.inUse) in use", "\($0.offline) offline"]
    } ?? [] : []
    if !freeDetail.isEmpty { sub = "" }
    var notes: [String] = []
    if charging { notes = ["Charging"] + [state.charging?.vehicle].compactMap { $0 } }
    else if status == "ACCEPT_PENDING" || CP_HELD.contains(status) {
        notes = [ans.big] + (state.snoozesLeft.map { [$0 > 0 ? "\($0) snooze\($0 == 1 ? "" : "s") left" : "No snoozes left"] } ?? [])
    }
    let stats = state.charging.map(cpChargingStats) ?? []
    var snapshot = CpSnapshot(
        site: state.location?.title ?? "ChargePoint",
        account: account,
        bigAnswer: ans.big,
        unit: unit,
        sub: sub,
        plugsFree: plugsFree,
        autoOn: state.autoOn && configured && !charging,
        actionLabel: ans.action,
        keys: cpManualKeys(state),
        deadline: expired ? nil : deadline,
        goTo: goTo,
        floors: configured && !charging && !assigned ? state.floors : [],
        checkedAt: checkedAt,
        freeDetail: freeDetail, showOpen: showPlugs,
        railNotes: notes, stats: stats,
        tone: .orange, autoControl: cpAutoControl(state))
    if configured, !charging, status == "PASS", deadline == nil || expired {
        // Local time retires the return promise, not the provider's queued PASS identity.
        snapshot.bigAnswer = "—"; snapshot.unit = ""
        snapshot.deadline = nil; snapshot.railNotes = []
        snapshot.sub = expired ? "Time elapsed\nRefresh to check" : "Deadline unknown\nRefresh to check"
        snapshot.statusDescription = expired ? "Time elapsed. Refresh to check." : "Deadline unknown. Refresh to check."
        snapshot.keys = [CpKey(command: "open", label: "Open ChargePoint"),
                         CpKey(command: "leave", label: "Leave")]
    }
    return snapshot
}

private func cpChargingStats(_ session: CpCharging) -> [CpStat] {
    var rows: [CpStat] = []
    if let miles = session.miles {
        rows.append(CpStat(label: "Est. distance", value: miles < 10 ? String(format: "%.1f mi", miles) : "\(Int(miles)) mi"))
    }
    if let seconds = session.seconds ?? session.minutes.map({ $0 * 60 }) {
        let time = seconds >= 3600 ? String(format: "%d h %02d", seconds / 3600, (seconds % 3600) / 60)
            : seconds >= 60 ? String(format: "%dm %02ds", seconds / 60, seconds % 60) : "\(seconds)s"
        rows.append(CpStat(label: "Time elapsed", value: time))
    }
    if let charger = session.charger, !charger.isEmpty {
        let name = [cpChargerShort(charger), cpLevelOf(charger)].compactMap { $0 }.joined(separator: " · ")
        rows.append(CpStat(label: "Charger", value: name))
    }
    return rows
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
