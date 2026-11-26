import Foundation

// The ChargePoint auto-waitlist engine — ported 1:1 from Android `ChargePointAuto.kt`. This is the
// PURE decision layer (the "auto state movement"): it decides what to do (accept / snooze-once /
// drive-now alert / wake later / done) from the current waitlist state. The *runtime* that acts on
// these steps is best-effort on iOS (see ChargePointRun / notes) — but this logic is exact.

public let CP_AUTO_MARGIN_MS: Int64 = 120_000      // act 2 min before each deadline
public let CP_AUTO_SNOOZE_SECONDS = 3600           // auto-snooze length (60 min)
public let CP_HELD: Set<String> = ["PENDING_PLUG_IN", "DIB_PENDING_PLUG_IN"]

/// A command the user or engine can issue. Carries the snooze length where relevant.
public enum CpCommand: Sendable, Equatable {
    case join, leave, accept, snooze(Int), unsnooze, start, stop, still, done, open, signin, location, auto, stopauto
}

/// What the engine decides to do this tick.
public enum CpAlert: Sendable, Equatable {
    case offer, secondOffer, accepted, snoozed   // user-gated (CpAlertPrefs)
    case driveNow, failed, signedOut, done        // operational — always sent
}
public enum CpAutoStep: Sendable, Equatable {
    case accept(CpRun)
    case snooze(CpRun)
    case wakeAt(Int64)              // ms-since-epoch to re-run the engine
    case alert(CpAlert, CpRun)
    case done
    case idle
}

/// The persisted auto-run record (Android `CpRun`). `startedAt` identifies a run so a late async
/// result can't rearm a paused/replaced run; `failedState`/`failedUntil` park a run after repeated
/// command failure so it isn't retried every poll until the user recovers it manually.
public struct CpRun: Sendable, Equatable {
    public var armed: Bool
    public var snoozeUsed: Bool
    public var drivePushed: Bool
    public var startedAt: Int64
    public var offerPushed: Bool
    public var failedState: String
    public var failedUntil: Int64?
    public var failedReason: String

    public init(armed: Bool = false, snoozeUsed: Bool = false, drivePushed: Bool = false,
                startedAt: Int64 = 0, offerPushed: Bool = false, failedState: String = "",
                failedUntil: Int64? = nil, failedReason: String = "") {
        self.armed = armed; self.snoozeUsed = snoozeUsed; self.drivePushed = drivePushed
        self.startedAt = startedAt; self.offerPushed = offerPushed; self.failedState = failedState
        self.failedUntil = failedUntil; self.failedReason = failedReason
    }
}

/// The core decision. Ported verbatim from `cpAutoDecide` (ChargePointAuto.kt:40-58).
public func cpAutoDecide(_ run: CpRun, state: String, untilMs: Int64?, snoozesLeft: Int?,
                         charging: Bool, now: Int64, marginMs: Int64 = CP_AUTO_MARGIN_MS) -> CpAutoStep {
    if !run.armed { return .idle }
    if charging || state == "CHARGING" { return .done }
    if run.failedState == state && run.failedUntil == untilMs { return .idle }

    // act now if within the margin of the deadline, else schedule a wake just before it
    func timed(_ act: CpAutoStep) -> CpAutoStep {
        guard let until = untilMs else { return .idle }
        return (until - now <= marginMs) ? act : .wakeAt(until - marginMs)
    }

    switch state {
    case "ACCEPT_PENDING":
        return timed(.accept(run))
    case let s where CP_HELD.contains(s):
        if (snoozesLeft ?? 0) > 0 && !run.snoozeUsed {
            var r = run; r.snoozeUsed = true
            return timed(.snooze(r))
        } else if run.drivePushed {
            return .idle
        } else {
            var r = run; r.drivePushed = true
            return .alert(.driveNow, r)
        }
    default:
        return .idle
    }
}

// ── Persisted-state helpers (all pure) ───────────────────────────────────────

/// The run to keep after acting on a step: on success the step carries the new run; on failure keep `before`.
public func cpAfterAct(_ before: CpRun, _ step: CpAutoStep, _ success: Bool) -> CpRun {
    guard success else { return before }
    switch step {
    case .accept(let r), .snooze(let r), .alert(_, let r): return r
    default: return before
    }
}

/// Only explicit Join-with-Auto resumes the run; manual choices preserve its mode and history.
public func cpArmForCommand(_ run: CpRun, _ command: CpCommand, autoRun: Bool, now: Int64) -> CpRun {
    if command == .join && autoRun { return cpResumeRun(run, nil, now) }
    return run
}

/// Manual waitlist commands preserve Auto. Pause and completed charging end unattended work.
public func cpManualEndsRun(_ command: CpCommand) -> Bool { false }

/// Pause keeps the run's history (so it can resume), just disarms it.
public func cpPauseRun(_ run: CpRun) -> CpRun { var r = run; r.armed = false; return r }

/// Resume: clear any parked failure, re-arm, and honour a spent snooze (from history or CP's count).
public func cpResumeRun(_ run: CpRun, _ snoozesLeft: Int?, _ now: Int64) -> CpRun {
    var r = clearedFailure(run)
    r.armed = true
    r.snoozeUsed = run.snoozeUsed || (snoozesLeft == 0)
    r.startedAt = run.startedAt == 0 ? now : run.startedAt
    return r
}

/// Fold a manual command into the run: Snooze spends the snooze; manual commands preserve mode/history.
/// A failed command (success == false) changes nothing.
public func cpAfterManual(_ run: CpRun, _ command: CpCommand, _ success: Bool) -> CpRun {
    guard success else { return run }
    switch command {
    case .snooze: var r = clearedFailure(run); r.snoozeUsed = true; return r
    default: return clearedFailure(run)
    }
}

/// Park the run after a command kept failing at this phase, so the engine stops retrying it.
public func cpRecordAutoFailure(_ run: CpRun, _ state: String, _ until: Int64?, _ reason: String) -> CpRun {
    var r = run; r.failedState = state; r.failedUntil = until; r.failedReason = reason; return r
}

/// Merge a (possibly late) auto result back onto the current run: ignore it if the run was paused to
/// a different identity or already reset; otherwise apply the step's result but keep the current
/// armed state (so a pause that happened meanwhile sticks).
public func cpMergeAutoResult(_ before: CpRun, _ current: CpRun, _ step: CpAutoStep, _ success: Bool) -> CpRun {
    cpMergeRunUpdate(before, current, cpAfterAct(before, step, success))
}

/// Merge an asynchronous refresh result without replacing newer user mode/history.
public func cpMergeRunUpdate(_ before: CpRun, _ current: CpRun, _ result: CpRun) -> CpRun {
    guard current.startedAt == before.startedAt, current != CpRun() else { return current }
    var merged = result
    merged.armed = current.armed && result.armed
    merged.snoozeUsed = merged.snoozeUsed || current.snoozeUsed
    merged.drivePushed = merged.drivePushed || current.drivePushed
    // Unlike snooze history, this flag resets between offer episodes.
    if current.offerPushed != before.offerPushed { merged.offerPushed = current.offerPushed }
    if current.failedState != before.failedState || current.failedUntil != before.failedUntil {
        merged.failedState = current.failedState
        merged.failedUntil = current.failedUntil
        merged.failedReason = current.failedReason
    }
    return merged
}

private func clearedFailure(_ run: CpRun) -> CpRun {
    var r = run; r.failedState = ""; r.failedUntil = nil; r.failedReason = ""; return r
}

// ── Wire format (persist a CpRun as one string) ──────────────────────────────

public func cpRunToWire(_ r: CpRun) -> String {
    [r.armed ? "1" : "0", r.snoozeUsed ? "1" : "0", r.drivePushed ? "1" : "0", String(r.startedAt),
     r.offerPushed ? "1" : "0", r.failedState, r.failedUntil.map(String.init) ?? "", r.failedReason]
        .joined(separator: "|")
}

public func cpRunFromWire(_ s: String) -> CpRun {
    if s.isEmpty { return CpRun() }
    let p = s.split(separator: "|", maxSplits: 7, omittingEmptySubsequences: false).map(String.init)
    guard p.count == 8 else { return CpRun() }
    return CpRun(armed: p[0] == "1", snoozeUsed: p[1] == "1", drivePushed: p[2] == "1",
                 startedAt: Int64(p[3]) ?? 0, offerPushed: p[4] == "1", failedState: p[5],
                 failedUntil: p[6].isEmpty ? nil : Int64(p[6]), failedReason: p[7])
}
