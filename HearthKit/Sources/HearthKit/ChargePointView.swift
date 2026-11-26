import Foundation

public enum CpAutoControl: String, Sendable, Codable { case stop, resume, join, signin, disabled }

public func cpAutoControl(_ state: CpState) -> CpAutoControl {
    var queued = false
    var charging = state.charging != nil
    if case let .inLine(_, status, _, _, _) = state.waitlist {
        queued = status != "UNKNOWN"
        charging = charging || status == "CHARGING"
    }
    if state.location == nil || charging { return .disabled }
    if state.signedOut || state.account.needsReauth { return .signin }
    if state.autoOn { return .stop }
    return queued ? .resume : .join
}

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
    public var floors: [CpFloor]
    /// nil means the allowance has not been confirmed, rather than an available snooze.
    public var snoozesLeft: Int?

    public init(signedOut: Bool, account: CpAccount, location: CpLocation?, now: CpNow?,
                waitlist: CpWaitlist, charging: CpCharging?, autoOn: Bool, floors: [CpFloor] = [],
                snoozesLeft: Int? = nil) {
        self.signedOut = signedOut; self.account = account; self.location = location; self.now = now
        self.waitlist = waitlist; self.charging = charging; self.autoOn = autoOn; self.floors = floors
        self.snoozesLeft = snoozesLeft
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
        let sub = c.powerKw.map { "\(fmt1($0)) kW now" } ?? "Reading pending"
        let energy = c.energyKwh.map { String(format: $0 < 1 ? "%.2f" : "%.1f", $0) } ?? "—"
        return CpAnswer(big: energy, unit: "kWh added", sub: sub, action: "Open")
    }
    // In line / offered / held.
    if case let .inLine(place, state, stations, offer, auto) = s.waitlist {
        switch state {
        case "ACCEPT_PENDING":
            let who = offer.map { $0.charger }.flatMap { $0.isEmpty ? nil : cpChargerShort($0) }
            return CpAnswer(big: "Your turn", unit: "", sub: who ?? "Respond now", action: "Open")
        case "PENDING_PLUG_IN", "DIB_PENDING_PLUG_IN":
            return CpAnswer(big: state == "DIB_PENDING_PLUG_IN" ? "Held again" : "Held for you",
                            unit: "", sub: "Plug in", action: "Open")
        case "PASS":
            return CpAnswer(big: "Snoozed", unit: "", sub: auto ? "Offer missed" : "Place kept", action: "Open")
        case "CHARGING":
            return CpAnswer(big: "—", unit: "kWh added", sub: "Reading pending", action: "Open")
        case "CHARGING_FAULT":
            return CpAnswer(big: "Not charging", unit: "to answer", sub: "Still need to charge?", action: "Open")
        case "DIB_PLUG_OUT":
            return CpAnswer(big: "Unplugged", unit: "to answer", sub: "Still need to charge?", action: "Open")
        case "PENDING_PLUG_OUT":
            return CpAnswer(big: "Done charging", unit: "Done", sub: "Move your car", action: "Open")
        case "OVER_STAYED":
            return CpAnswer(big: "Move your car", unit: "to move", sub: "Move your car", action: "Open")
        case "BLOCKED":
            return CpAnswer(big: "Blocked", unit: "", sub: "ChargePoint says so", action: "Open")
        case "PENDING":
            let opens = offer.flatMap { $0.startMs > 0 ? Date(timeIntervalSince1970: Double($0.startMs) / 1000) : nil }
            return CpAnswer(big: opens.map(cpClockString) ?? "Soon", unit: "waitlist opens",
                            sub: "\(stations > 0 ? stations : s.location?.deviceIds.count ?? 0) chargers", action: "Open")
        default: // WAITING and the like
            let chargers = stations > 0 ? stations : (s.location?.deviceIds.count ?? 0)
            return CpAnswer(big: place.map { "#\($0)" } ?? "In line",
                            unit: place != nil ? "in line" : "",
                            sub: "\(chargers) charger\(chargers == 1 ? "" : "s")", action: "Open")
        }
    }
    // Signed in, idle. Without a chosen location we can't show plug counts → prompt to set one.
    if s.location == nil {
        return CpAnswer(big: "Set up", unit: "", sub: "Choose a location", action: "Choose location")
    }
    guard let reading = s.now else {
        return CpAnswer(big: "—", unit: "plugs free", sub: "Reading pending", action: "Join")
    }
    return CpAnswer(big: "\(reading.free)", unit: "plugs free", sub: "of \(reading.total) plugs", action: "Join")
}

/// A state-specific manual command button on the ChargePoint card (the iOS take on Android's key
/// row). Held spots open the companion app; only a confirmed allowance exposes Snooze.
public struct CpKey: Sendable, Equatable, Codable {
    public let command: String   // accept | snooze | leave | unsnooze
    public let label: String
    public init(command: String, label: String) { self.command = command; self.label = label }
}

/// The deadline to count down to, for timed states that carry an offer/hold/snooze clock.
public func cpDeadline(_ s: CpState) -> Date? {
    guard case let .inLine(_, state, _, offer?, _) = s.waitlist,
          ["ACCEPT_PENDING", "PENDING_PLUG_IN", "DIB_PENDING_PLUG_IN", "PASS", "CHARGING_FAULT",
           "DIB_PLUG_OUT", "PENDING_PLUG_OUT", "OVER_STAYED"].contains(state),
          offer.untilMs > 0 else { return nil }
    return Date(timeIntervalSince1970: Double(offer.untilMs) / 1000)
}

/// SwiftUI timer ranges must remain ordered, including when a cached offer has expired.
public func cpCountdownInterval(until deadline: Date, now: Date = Date()) -> ClosedRange<Date>? {
    deadline > now ? now...deadline : nil
}

public func cpManualKeys(_ s: CpState) -> [CpKey] {
    if s.signedOut || s.account.needsReauth { return [] }
    if let charging = s.charging {
        return [charging.canStop ? CpKey(command: "stop", label: "Stop") : CpKey(command: "open", label: "Open ChargePoint")]
    }
    guard case let .inLine(_, state, _, _, _) = s.waitlist else { return [] }
    switch state {
    case "ACCEPT_PENDING":
        return [CpKey(command: "accept", label: "Accept"),
                (s.snoozesLeft ?? 0) > 0 ? CpKey(command: "snooze", label: "Snooze") : CpKey(command: "leave", label: "Leave")]
    case "PENDING_PLUG_IN", "DIB_PENDING_PLUG_IN":
        return [CpKey(command: "open", label: "Open ChargePoint"),
                (s.snoozesLeft ?? 0) > 0 ? CpKey(command: "snooze", label: "Snooze") : CpKey(command: "leave", label: "Leave")]
    case "PASS": return [CpKey(command: "unsnooze", label: "Rejoin"), CpKey(command: "leave", label: "Leave")]
    case "CHARGING", "PENDING_PLUG_OUT", "OVER_STAYED": return [CpKey(command: "open", label: "Open ChargePoint")]
    case "CHARGING_FAULT", "DIB_PLUG_OUT": return [CpKey(command: "still", label: "Keep charging"), CpKey(command: "done", label: "I'm done")]
    default: return [CpKey(command: "leave", label: "Leave")]
    }
}
