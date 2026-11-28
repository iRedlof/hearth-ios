import Foundation

/// How long an idle ChargePoint widget waits before asking to be refreshed.
public let CP_RELOAD_IDLE_SECONDS: TimeInterval = 15 * 60
/// While Auto is armed and the person is in line, look in more often.
public let CP_RELOAD_ARMED_SECONDS: TimeInterval = 5 * 60
/// After a step was due on this run (it may have failed or still be in flight), look again soon.
public let CP_RELOAD_AFTER_ACTION_SECONDS: TimeInterval = 60
/// Land just inside the moment being waited for, not on its edge.
public let CP_WAKE_SLACK_SECONDS: TimeInterval = 5

/// When ChargePoint should run next. Android wakes itself with an exact alarm at
/// `CpAutoStep.WakeAt`; iOS has no such alarm, so the widget asks WidgetKit — and the app asks the
/// system — to come back at this time instead of on a flat interval. A flat 15 minutes could land
/// before a 2-minute action window opened and again after the offer had ended.
public func cpNextReload(run: CpRun, phase: String, deadlineMs: Int64?, snoozesLeft: Int?,
                         charging: Bool, now: Date) -> Date {
    let nowMs = Int64((now.timeIntervalSince1970 * 1000).rounded())
    let queued = !charging && !["NOT_QUEUED", "UNKNOWN", "", "CHARGING"].contains(phase)
    let interval = run.armed && queued ? CP_RELOAD_ARMED_SECONDS : CP_RELOAD_IDLE_SECONDS
    var wait = interval

    if run.armed {
        switch cpAutoDecide(run, state: phase, untilMs: deadlineMs, snoozesLeft: snoozesLeft,
                            charging: charging, now: nowMs) {
        case .wakeAt(let ms):
            wait = min(wait, TimeInterval(ms - nowMs) / 1000 + CP_WAKE_SLACK_SECONDS)
        case .accept, .snooze:
            wait = min(wait, CP_RELOAD_AFTER_ACTION_SECONDS)
        case .alert, .done, .idle:
            break
        }
    } else if let deadlineMs, phase == "ACCEPT_PENDING" || CP_HELD.contains(phase) {
        // Nobody acts for the person, but the card must stop saying "your turn" when it is over.
        wait = min(wait, TimeInterval(deadlineMs - nowMs) / 1000 + CP_WAKE_SLACK_SECONDS)
    }
    return now.addingTimeInterval(max(wait, CP_WAKE_SLACK_SECONDS))
}

public extension CpStoreSnapshot {
    /// `cpNextReload` for what is stored now.
    func nextReload(now: Date) -> Date {
        let provider = reading?.provider
        var phase = "NOT_QUEUED"
        var deadline: Int64?
        if case .inLine(_, let state, _, let offer, _)? = provider?.waitlist {
            phase = state
            deadline = offer.map { Int64($0.untilMs) }
        }
        return cpNextReload(run: run, phase: phase, deadlineMs: deadline, snoozesLeft: provider?.snoozesLeft,
                            charging: provider?.charging != nil, now: now)
    }
}
