import Foundation

/// The core ChargePoint state the card is drawn from. (The Android `CpCard`/`CpRun` carry much more —
/// the full offer/accept/snooze/retry machinery, floor levels, live countdown. This models the states
/// the Beacon hero actually shows; see CpSnapshotMapping for what is summarized.)
public struct CpState: Sendable, Equatable {
    public var signedOut: Bool
    public var account: CpAccount
    public var location: CpLocation?
    public var now: CpNow?
    public var waitlist: CpWaitlist
    public var charging: CpCharging?
    public var autoOn: Bool

    public init(signedOut: Bool, account: CpAccount, location: CpLocation?, now: CpNow?,
                waitlist: CpWaitlist, charging: CpCharging?, autoOn: Bool) {
        self.signedOut = signedOut; self.account = account; self.location = location; self.now = now
        self.waitlist = waitlist; self.charging = charging; self.autoOn = autoOn
    }
}

/// The hero answer + unit + secondary line + action label for a core state (a faithful summary of the
/// Android `cpBeaconView` hero/detail, minus the live-countdown and offer-timing deadlines).
public struct CpAnswer: Sendable, Equatable {
    public var big: String
    public var unit: String
    public var sub: String
    public var action: String
}

private func fmt1(_ d: Double) -> String {
    String(format: "%.1f", d)
}

public func cpAnswer(_ s: CpState) -> CpAnswer {
    // Signed out / join-session expired → the hero is the sign-in prompt.
    if s.signedOut || s.account.needsReauth {
        let sub = s.account.text.contains("Signed out") ? "Session expired" : "Use its own sign-in page"
        return CpAnswer(big: "Sign in", unit: "", sub: sub, action: "Sign in")
    }
    // Charging → the hero is the live session.
    if let c = s.charging {
        let sub = c.powerKw.map { "\(fmt1($0)) kW" } ?? "Reading pending"
        return CpAnswer(big: "Charging", unit: c.energyKwh.map { "\(fmt1($0)) kWh added" } ?? "", sub: sub, action: "Open")
    }
    // In line / offered / held.
    if case let .inLine(place, state, stations, offer, auto) = s.waitlist {
        switch state {
        case "ACCEPT_PENDING":
            let who = offer.map { $0.charger }.flatMap { $0.isEmpty ? nil : cpChargerShort($0) }
            return CpAnswer(big: "Your turn", unit: "", sub: who ?? "Respond now", action: "Open")
        case "PENDING_PLUG_IN", "DIB_PENDING_PLUG_IN":
            return CpAnswer(big: "Held", unit: "", sub: "Plug in", action: "Open")
        case "PASS":
            return CpAnswer(big: "Passed", unit: "", sub: auto ? "Offer missed" : "Place kept", action: "Open")
        default: // WAITING and the like
            let chargers = stations > 0 ? stations : (s.location?.deviceIds.count ?? 0)
            return CpAnswer(big: place.map { "#\($0)" } ?? "In line",
                            unit: place != nil ? "in line" : "",
                            sub: "\(chargers) charger\(chargers == 1 ? "" : "s")", action: "Open")
        }
    }
    // Signed in, idle. Without a chosen location we can't show plug counts → prompt to set one.
    if s.location == nil {
        return CpAnswer(big: "Set up", unit: "", sub: "Choose a location", action: "Open")
    }
    let free = s.now?.free ?? 0
    return CpAnswer(big: "\(free)", unit: "plugs free", sub: "\(s.now?.stations ?? 0) chargers", action: "Join")
}

/// A state-specific manual command button on the ChargePoint card (the iOS take on Android's key
/// row). Only the no-argument commands are surfaced; Start/Stop (which need session/device ids) are
/// left to "Open" in the ChargePoint app, and the auto engine handles automated accept/snooze.
public struct CpKey: Sendable, Equatable {
    public let command: String   // accept | snooze | leave | unsnooze
    public let label: String
    public init(command: String, label: String) { self.command = command; self.label = label }
}

/// The deadline to count down to, for timed states that carry an offer/hold/snooze clock.
public func cpDeadline(_ s: CpState) -> Date? {
    guard case let .inLine(_, state, _, offer?, _) = s.waitlist,
          ["ACCEPT_PENDING", "PENDING_PLUG_IN", "DIB_PENDING_PLUG_IN", "PASS"].contains(state),
          offer.untilMs > 0 else { return nil }
    return Date(timeIntervalSince1970: Double(offer.untilMs) / 1000)
}

public func cpManualKeys(_ s: CpState) -> [CpKey] {
    if s.signedOut || s.account.needsReauth { return [] }
    if s.charging != nil { return [CpKey(command: "stop", label: "Stop")] }
    guard case let .inLine(_, state, _, _, _) = s.waitlist else { return [] }
    switch state {
    case "ACCEPT_PENDING": return [CpKey(command: "accept", label: "Accept"), CpKey(command: "snooze", label: "Snooze")]
    case "PENDING_PLUG_IN", "DIB_PENDING_PLUG_IN": return [CpKey(command: "start", label: "Start"), CpKey(command: "snooze", label: "Snooze")]
    case "PASS": return [CpKey(command: "unsnooze", label: "Rejoin")]
    case "CHARGING_FAULT", "DIB_PLUG_OUT": return [CpKey(command: "still", label: "Keep charging"), CpKey(command: "done", label: "I'm done")]
    default: return [CpKey(command: "leave", label: "Leave")]
    }
}
