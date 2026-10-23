import Foundation

public func statusFor(_ state: String?) -> StatusView {
    switch state {
    case "disarmed":            return StatusView("Disarmed", .calm)
    case "armed_home":          return StatusView("Armed home", .home)
    case "armed_away":          return StatusView("Armed away", .away)
    case "armed_night":         return StatusView("Armed night", .home)
    case "armed_vacation":      return StatusView("Armed vacation", .away)
    case "armed_custom_bypass": return StatusView("Armed (bypass)", .home)
    case "arming":              return StatusView("Arming…", .busy)
    case "disarming":           return StatusView("Disarming…", .busy)
    case "pending":             return StatusView("Entry delay", .busy)
    case "triggered":           return StatusView("Alarm triggered", .alert)
    case nil:                   return StatusView("—", .unknown)
    default:                    return StatusView("Unavailable", .unknown)
    }
}

/// "since 9:42 AM" today, "since Mon 9:42 PM" this week, else "since Oct 3".
public func sinceLabel(_ changed: Date?, now: Date, zone: TimeZone = .current, locale: Locale = .current) -> String? {
    guard let changed else { return nil }
    var cal = Calendar(identifier: .gregorian); cal.timeZone = zone
    let days = cal.dateComponents([.day], from: cal.startOfDay(for: changed), to: cal.startOfDay(for: now)).day ?? 0
    let pattern = days == 0 ? "h:mm a" : (days >= 1 && days <= 6 ? "EEE h:mm a" : "MMM d")
    let fmt = DateFormatter(); fmt.locale = locale; fmt.timeZone = zone; fmt.dateFormat = pattern
    return "since " + fmt.string(from: changed)
}

/// The status row, honestly: live state + when it changed; on error the last known state greyed with
/// when it was last checked; never a made-up state.
public func cardFor(_ state: String?, error: String?, changedAt: Date?, checkedAt: Date?, now: Date,
                    zone: TimeZone = .current, locale: Locale = .current) -> CardView {
    if let error, error.hasPrefix("Set up") { return CardView("Set up", .unknown, "Tap to connect") }
    if let error {
        if state == nil { return CardView("—", .unknown, error) }
        let checked = sinceLabel(checkedAt, now: now, zone: zone, locale: locale)?
            .replacingOccurrences(of: "since ", with: "last checked ")
        let detail = [error, checked].compactMap { $0 }.joined(separator: "\n")
        return CardView(statusFor(state).title, .unknown, detail)
    }
    let view = statusFor(state)
    let detail: String?
    switch state {
    case "arming":  detail = "Exit delay"
    case "pending": detail = "Entry delay"
    default:        detail = changedLabel(eventWord(state), at: changedAt, now: now, zone: zone, locale: locale)
    }
    return CardView(view.title, view.tone, detail)
}

/// True when the card shows a greyed, last-known state because the refresh failed.
public func alarmStale(_ state: String?, _ error: String?) -> Bool {
    guard let error, !error.hasPrefix("Set up") else { return false }
    return state != nil
}

public func actionsFor(_ state: String?) -> [AlarmAction] {
    switch state {
    case "disarmed": return [.armHome, .armAway]
    case "armed_home", "armed_away", "armed_night", "armed_vacation", "armed_custom_bypass",
         "arming", "disarming", "pending", "triggered": return [.disarm]
    default: return AlarmAction.allCases
    }
}

public func eventWord(_ state: String?) -> String {
    switch state {
    case "disarmed": return "Disarmed"
    case "armed_home", "armed_away", "armed_night", "armed_vacation", "armed_custom_bypass": return "Armed"
    case "triggered": return "Triggered"
    case "locked": return "Locked"
    case "unlocked": return "Unlocked"
    case "jammed": return "Jammed"
    case "open": return "Opened"
    default: return "Changed"
    }
}

/// "Armed at 8:35 PM" (today), "Armed Mon 8:35 PM" (this week), "Armed Oct 3".
public func changedLabel(_ word: String, at: Date?, now: Date, zone: TimeZone = .current, locale: Locale = .current) -> String? {
    guard let at, let since = sinceLabel(at, now: now, zone: zone, locale: locale) else { return nil }
    let time = String(since.dropFirst("since ".count))
    var cal = Calendar(identifier: .gregorian); cal.timeZone = zone
    return cal.isDate(at, inSameDayAs: now) ? "\(word) at \(time)" : "\(word) \(time)"
}

// ── Front door lock ──────────────────────────────────────────────────────────
public func lockStatusFor(_ state: String?) -> LockView {
    switch state {
    case "locked":    return LockView("Locked", true)
    case "unlocked":  return LockView("Unlocked", false)
    case "open":      return LockView("Open", false)
    case "jammed":    return LockView("Jammed", false)
    case "locking":   return LockView("Locking…", nil)
    case "unlocking": return LockView("Unlocking…", nil)
    case "opening":   return LockView("Opening…", nil)
    case nil:         return LockView("—", nil)
    default:          return LockView("Unavailable", nil)
    }
}

public func lockActionFor(_ state: String?) -> LockAction? {
    switch state {
    case "locked": return .unlock
    case "locking", "unlocking", "opening": return nil
    default: return .lock
    }
}

// ── Beacon tone + glyph ──────────────────────────────────────────────────────
public func beaconAlarmPair(_ state: String?, stale: Bool) -> BeaconTone {
    if stale { return .offline }
    switch state {
    case "disarmed": return .blue
    case "triggered": return .triggered
    case "armed_home", "armed_away", "armed_night", "armed_vacation", "armed_custom_bypass",
         "arming", "disarming", "pending": return .red
    default: return .offline
    }
}

/// The shield glyph for a tone (Android `statusIcon`: Busy reuses the lock shield).
public func beaconAlarmGlyph(_ tone: Tone) -> AlarmGlyph {
    switch tone {
    case .calm: return .off
    case .home: return .home
    case .away, .busy: return .lock
    case .alert, .unknown: return .alert
    }
}
