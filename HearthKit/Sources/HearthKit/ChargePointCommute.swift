import Foundation

// The ChargePoint morning-commute auto-join decision — ported 1:1 from Android `ChargePointCommute.kt`.
// This is the PURE decision layer: it decides what to do (arm auto-run, nudge sign-in, or do nothing)
// from Home Assistant's two ETA booleans plus ChargePoint state plus once-per-morning debounce dates.
// All timing/zone/ETA logic is computed in Home Assistant's template sensors; this only branches.

/// A day stamp for once-per-morning debounce. Represented as Int yyyymmdd (e.g., 20261027) to make
/// day-equality trivial and computation from `@Dependency(\.date)` straightforward.
public typealias CommuteDay = Int

/// What the commute auto-join should do on this poll.
public enum CommuteAction: Sendable, Equatable {
    case armAuto        // arm the auto-run (join waitlist with auto-accept enabled)
    case notifySignIn   // nudge user to sign in (session expired, but approaching ETA)
    case none           // do nothing (not enabled, already acted today, or conditions not met)
}

/**
 Decide the commute action from Home Assistant's two booleans plus ChargePoint run state and
 once-per-morning debounce. Pure: all time/zone/ETA logic is computed in HA's template sensors.

 - Parameter enabled: Feature toggle (global commute auto-join setting).
 - Parameter chargeNow: HA `binary_sensor.commute_charge_now` (weekday 09–11, away, ETA ≤ 30 min).
 - Parameter signinNeeded: HA `binary_sensor.commute_signin_needed` (same but ETA ≤ 45 min, earlier margin).
 - Parameter alreadyArmed: ChargePoint auto-run is currently armed (don't re-arm).
 - Parameter charging: Vehicle is currently charging (auto-run already succeeded, or manual start).
 - Parameter signedOutOrExpired: ChargePoint session is signed out or expired (can't arm, nudge sign-in instead).
 - Parameter lastArmDay: Day stamp (yyyymmdd) of last `.armAuto` action, for once-per-morning debounce.
 - Parameter lastNotifyDay: Day stamp (yyyymmdd) of last `.notifySignIn` action, for once-per-morning debounce.
 - Parameter today: Current day stamp (yyyymmdd), from `@Dependency(\.date)` in `TimeZone.current`.
 - Returns: The action to take (armAuto, notifySignIn, or none).

 Logic ported verbatim from Android `commuteDecide` (ChargePointCommute.kt:21-38):
 1. If not enabled → none.
 2. If signed out/expired → notifySignIn IF signinNeeded AND haven't notified today, else none.
 3. If chargeNow AND not already armed AND not charging AND haven't armed today → armAuto.
 4. Otherwise → none.
 */
public func commuteDecide(
    enabled: Bool,
    chargeNow: Bool,
    signinNeeded: Bool,
    alreadyArmed: Bool,
    charging: Bool,
    signedOutOrExpired: Bool,
    lastArmDay: CommuteDay?,
    lastNotifyDay: CommuteDay?,
    today: CommuteDay
) -> CommuteAction {
    if !enabled { return .none }
    if signedOutOrExpired {
        return (signinNeeded && lastNotifyDay != today) ? .notifySignIn : .none
    }
    if chargeNow && !alreadyArmed && !charging && lastArmDay != today {
        return .armAuto
    }
    return .none
}
