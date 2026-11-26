import Foundation

/// Which auto-waitlist alerts the user wants (ported from Android's `note_*` prefs — all default ON).
/// The four events here are the "Alert ·" toggles in Settings. Drive-now / failed / signed-out / done
/// are not represented: they always fire (see `cpAlertAllowed`), matching Android's "Always alerts" row.
public struct CpAlertPrefs: Sendable, Equatable {
    public var offer: Bool
    public var accepted: Bool
    public var snoozed: Bool
    public var second: Bool

    public init(offer: Bool = true, accepted: Bool = true, snoozed: Bool = true, second: Bool = true) {
        self.offer = offer
        self.accepted = accepted
        self.snoozed = snoozed
        self.second = second
    }
}

/// Should this alert be posted given the user's prefs? The four gated events honor their toggle; the
/// operational ones always fire. Mirrors Android `cpAutoShouldNotify`.
public func cpAlertAllowed(_ alert: CpAlert, prefs: CpAlertPrefs) -> Bool {
    switch alert {
    case .offer: return prefs.offer
    case .secondOffer: return prefs.second
    case .accepted: return prefs.accepted
    case .snoozed: return prefs.snoozed
    case .driveNow, .failed, .signedOut, .done: return true
    }
}

/// A ready-to-post local notification: title/body already substituted, plus a stable id for de-dupe.
public struct CpAlertContent: Sendable, Equatable {
    public let title: String
    public let body: String
    public let id: String

    public init(title: String, body: String, id: String) {
        self.title = title
        self.body = body
        self.id = id
    }
}

/// The verbatim ChargePoint auto copy (ported from Android `cpAutoNote`). `who` = short charger name
/// or "your charger"; `by` = the deadline clock or "the deadline" (see `cpAlertSubjects`).
public func cpAlertContent(_ alert: CpAlert, who: String, by: String) -> CpAlertContent {
    switch alert {
    case .offer:
        return CpAlertContent(title: "Your turn", body: "I'll accept \(who) at the deadline.", id: "cp.offer")
    case .secondOffer:
        return CpAlertContent(title: "Your turn again", body: "I'll accept — no snooze left after this.", id: "cp.second")
    case .accepted:
        return CpAlertContent(title: "Accepted \(who)", body: "Held — plug in by \(by). I'll take the next step.", id: "cp.accepted")
    case .snoozed:
        return CpAlertContent(title: "Snoozed", body: "Back in line about an hour. Still automating.", id: "cp.snoozed")
    case .driveNow:
        return CpAlertContent(title: "🚗 Drive now", body: "Spot held — plug in by \(by). No snooze left.", id: "cp.driveNow")
    case .failed:
        return CpAlertContent(title: "Couldn't do it — your turn", body: "Tap to handle it yourself before \(by).", id: "cp.failed")
    case .signedOut:
        return CpAlertContent(title: "Signed out of ChargePoint", body: "Sign in again to keep the widget live.", id: "cp.signedOut")
    case .done:
        return CpAlertContent(title: "Charging — all set", body: "Auto-waitlist done.", id: "cp.done")
    }
}

/// Derive the `who` / `by` substitutions from a `userStatus` body: the current offer's charger
/// short-name and deadline clock, each with a graceful fallback when the offer isn't present.
public func cpAlertSubjects(_ statusJson: String) -> (who: String, by: String) {
    guard case let .inLine(_, _, _, offer?, _) = cpWaitlistFrom(statusJson, nil) else {
        return ("your charger", "the deadline")
    }
    let short = cpChargerShort(offer.charger)
    let who = short.isEmpty ? "your charger" : short
    let by = offer.untilMs > 0
        ? cpClockString(Date(timeIntervalSince1970: Double(offer.untilMs) / 1000))
        : "the deadline"
    return (who, by)
}
