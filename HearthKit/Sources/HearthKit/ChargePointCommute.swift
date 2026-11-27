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

 - Parameter autojoinEnabled: Gates the armAuto branch (auto-join on my commute).
 - Parameter checkBeforeLeaveEnabled: Gates the notifySignIn branch (check before I leave).
 - Parameter chargeNow: HA `binary_sensor.commute_charge_now` (weekday 09–11, away, ETA ≤ 30 min).
 - Parameter signinNeeded: HA `binary_sensor.commute_signin_needed` (same but ETA ≤ 45 min, earlier margin).
 - Parameter alreadyArmed: ChargePoint auto-run is currently armed (don't re-arm).
 - Parameter charging: Vehicle is currently charging (auto-run already succeeded, or manual start).
 - Parameter signedOutOrExpired: ChargePoint session is signed out or expired (can't arm, nudge sign-in instead).
 - Parameter lastArmDay: Day stamp (yyyymmdd) of last `.armAuto` action, for once-per-morning debounce.
 - Parameter lastNotifyDay: Day stamp (yyyymmdd) of last `.notifySignIn` action, for once-per-morning debounce.
 - Parameter today: Current day stamp (yyyymmdd), from `@Dependency(\.date)` in `TimeZone.current`.
 - Returns: The action to take (armAuto, notifySignIn, or none).

 Two independent toggles:
 1. Auto-join: IF autojoinEnabled AND signed in AND chargeNow AND not armed AND not charging AND haven't armed today → armAuto.
 2. Check-before-leave: IF checkBeforeLeaveEnabled AND signed out AND signinNeeded AND haven't notified today → notifySignIn.
 3. Otherwise → none.
 */
public func commuteDecide(
    autojoinEnabled: Bool,
    checkBeforeLeaveEnabled: Bool,
    chargeNow: Bool,
    signinNeeded: Bool,
    alreadyArmed: Bool,
    charging: Bool,
    signedOutOrExpired: Bool,
    lastArmDay: CommuteDay?,
    lastNotifyDay: CommuteDay?,
    today: CommuteDay
) -> CommuteAction {
    // Check-before-leave: notify branch (only when that feature is enabled)
    if checkBeforeLeaveEnabled && signedOutOrExpired && signinNeeded && lastNotifyDay != today {
        return .notifySignIn
    }
    // Auto-join: arm branch (only when that feature is enabled)
    if autojoinEnabled && !signedOutOrExpired && chargeNow && !alreadyArmed && !charging && lastArmDay != today {
        return .armAuto
    }
    return .none
}

/**
 Convert a Date to a CommuteDay (yyyymmdd Int) in the given timezone.

 CRITICAL: Uses Calendar with the passed TimeZone, NOT UTC/ISO8601DateFormatter (off-by-one gotcha).
 This ensures day boundaries respect the local timezone where the user experiences them.

 - Parameter date: The date to convert.
 - Parameter timeZone: The timezone to use for day calculation.
 - Returns: The day stamp as yyyymmdd Int (e.g., 20261027 for Oct 27, 2026).
 */
public func commuteDay(from date: Date, in timeZone: TimeZone) -> CommuteDay {
    var calendar = Calendar.current
    calendar.timeZone = timeZone

    let components = calendar.dateComponents([.year, .month, .day], from: date)

    guard let year = components.year,
          let month = components.month,
          let day = components.day else {
        // Should never happen with a valid date, but provide a fallback
        return 0
    }

    return year * 10000 + month * 100 + day
}

/**
 Parse the HA commute sensor template response (`True|False`) into a tuple of booleans.

 Home Assistant's `/api/template` renders `{{ is_state(...) }}` as Python-style capitalized
 `True`/`False`. This parser matches Android's semantics (ChargePointCommute.kt:67-70):
 - Trim the body and each token of whitespace/newlines (HA responses can carry trailing newlines).
 - Exactly two pipe-separated parts → parse; otherwise → `nil` (malformed shape).
 - Each token is case-insensitively compared to `"true"`; non-"true" → `false` (not `nil`).

 - Parameter body: The template response (e.g., `"True|False"`, `"True|False\n"`).
 - Returns: A tuple `(chargeNow: Bool, signinNeeded: Bool)` on success, `nil` on malformed shape.

 Malformed shape (wrong token count, empty string) returns `nil`. Valid shape with non-"true"
 tokens returns a result with `false` for those positions (matches Android).
 */
public func parseCommuteSensors(_ body: String) -> (chargeNow: Bool, signinNeeded: Bool)? {
    let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
    let tokens = trimmed.split(separator: "|").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
    guard tokens.count == 2 else { return nil }

    let chargeNow = tokens[0].lowercased() == "true"
    let signinNeeded = tokens[1].lowercased() == "true"

    return (chargeNow: chargeNow, signinNeeded: signinNeeded)
}

/// Status of the morning-commute sensor detection.
public enum CommuteStatus: Sendable, Equatable {
    case found              // fresh sensor read (within threshold)
    case lastHeard(Date)    // stale sensor read (older than threshold)
    case waiting            // never heard from sensor (nil)
}

/**
 Map the last sensor read timestamp to a UI-facing status.

 - Parameter lastHeard: The timestamp of the last sensor read from HA, or `nil` if never heard.
 - Parameter now: Current time (from `@Dependency(\.date)` in production).
 - Parameter threshold: Freshness window in seconds (default 300 = 5 minutes).
 - Returns: Status enum representing found/lastHeard/waiting state.

 Logic:
 - `nil` → `.waiting` (never heard from sensor).
 - Fresh (age ≤ threshold) → `.found` (sensor is active).
 - Stale (age > threshold) → `.lastHeard(date)` (sensor went silent).

 Threshold is exclusive: exactly at threshold is considered stale.
 */
public func commuteStatus(lastHeard: Date?, now: Date, threshold: TimeInterval = 300) -> CommuteStatus {
    guard let lastHeard else {
        return .waiting
    }

    let age = now.timeIntervalSince(lastHeard)

    if age < threshold {
        return .found
    } else {
        return .lastHeard(lastHeard)
    }
}
