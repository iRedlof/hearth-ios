import Foundation

/// Illustrative gallery conditions, with no session or provider authority.
public enum CpWidgetPreviewExample: String, CaseIterable, Identifiable, Sendable {
    case heldSnoozeAvailable
    case heldNoSnoozes
    case sessionExpiredSignInRequired

    case available
    case signed_out
    case no_location
    case waiting
    case auto_waiting
    case pending
    case offer
    case offer_last
    case held
    case held_unknown
    case dib_held
    case offer_no_floor
    case unknown_deadline
    case snoozed
    case auto_snoozed
    case charging
    case charging_no_stop
    case done
    case fault
    case unplugged
    case overstayed
    case blocked

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .heldSnoozeAvailable: "Spot held · snooze available"
        case .heldNoSnoozes: "Spot held · no snoozes left"
        case .sessionExpiredSignInRequired: "Session expired · sign in required"
        case .available: "Plugs available"
        case .signed_out: "Signed out"
        case .no_location: "Choose a location"
        case .waiting: "In line · Auto off"
        case .auto_waiting: "In line · Auto on"
        case .pending: "Waitlist opens later"
        case .offer: "Offer ready · snooze available"
        case .offer_last: "Offer ready · no snoozes left"
        case .held: "Spot held · Auto off"
        case .held_unknown: "Spot held · allowance unknown"
        case .dib_held: "Spot held again"
        case .offer_no_floor: "Offer ready · charger name"
        case .unknown_deadline: "Offer deadline unknown"
        case .snoozed: "Snoozed · Auto off"
        case .auto_snoozed: "Snoozed · Auto on"
        case .charging: "Charging · Stop available"
        case .charging_no_stop: "Charging · open app"
        case .done: "Charging complete"
        case .fault: "Charging stopped"
        case .unplugged: "Unplugged"
        case .overstayed: "Move your car"
        case .blocked: "Charger blocked"
        }
    }
}

/// `now` is the retained gallery-visit reference, not a replacement for the live countdown clock.
public func cpWidgetPreviewState(_ example: CpWidgetPreviewExample, now: Date) -> CpState {
    if ![CpWidgetPreviewExample.heldSnoozeAvailable, .heldNoSnoozes,
          .sessionExpiredSignInRequired].contains(example) {
        return cpAdditionalWidgetPreviewState(example, now: now)
    }
    let location = CpLocation(name: "Workplace", address: "", deviceIds: [],
                              bounds: cpBounds(lat: 0, lon: 0))
    let expired = example == .sessionExpiredSignInRequired
    let offer = CpOffer(deviceId: 0, port: 0, charger: "EXAMPLE-29 P3",
                        untilMs: Int64(now.addingTimeInterval(1_800).timeIntervalSince1970 * 1_000))
    return CpState(
        signedOut: false,
        account: cpAccount(hasSession: true, expired: false, joinExpired: expired),
        location: location,
        now: nil,
        waitlist: expired ? .notQueued : .inLine(place: nil, state: "PENDING_PLUG_IN",
                                                stations: 0, offer: offer, auto: false),
        charging: nil,
        autoOn: true,
        snoozesLeft: expired ? nil : example == .heldNoSnoozes ? 0 : 1)
}

/// Derive every displayed fact and action through the same pure mapper as production.
public func cpWidgetPreviewSnapshot(_ example: CpWidgetPreviewExample, now: Date) -> CpSnapshot {
    cpSnapshot(cpWidgetPreviewState(example, now: now), email: "example",
               checkedAt: cpClockString(now), now: now)
}

/// Existing coherent pure conditions; deliberately excludes owned operation/expired overlays.
private func cpAdditionalWidgetPreviewState(_ example: CpWidgetPreviewExample, now: Date) -> CpState {
    let phase: String?
    let allowance: Int?
    let auto: Bool
    switch example {
    case .waiting: (phase, allowance, auto) = ("WAITING", nil, false)
    case .auto_waiting: (phase, allowance, auto) = ("WAITING", nil, true)
    case .offer, .offer_no_floor: (phase, allowance, auto) = ("ACCEPT_PENDING", 1, false)
    case .offer_last: (phase, allowance, auto) = ("ACCEPT_PENDING", 0, false)
    case .held: (phase, allowance, auto) = ("PENDING_PLUG_IN", 1, false)
    case .held_unknown: (phase, allowance, auto) = ("PENDING_PLUG_IN", nil, false)
    case .dib_held: (phase, allowance, auto) = ("DIB_PENDING_PLUG_IN", 1, false)
    case .snoozed: (phase, allowance, auto) = ("PASS", nil, false)
    case .auto_snoozed: (phase, allowance, auto) = ("PASS", nil, true)
    case .charging, .charging_no_stop: (phase, allowance, auto) = ("CHARGING", nil, false)
    case .done: (phase, allowance, auto) = ("PENDING_PLUG_OUT", nil, false)
    case .fault: (phase, allowance, auto) = ("CHARGING_FAULT", nil, false)
    case .unplugged: (phase, allowance, auto) = ("DIB_PLUG_OUT", nil, false)
    case .overstayed: (phase, allowance, auto) = ("OVER_STAYED", nil, false)
    case .blocked: (phase, allowance, auto) = ("BLOCKED", nil, false)
    case .pending: (phase, allowance, auto) = ("PENDING", nil, false)
    case .unknown_deadline: (phase, allowance, auto) = ("ACCEPT_PENDING", 1, true)
    default: (phase, allowance, auto) = (nil, nil, false)
    }
    let signedOut = example == .signed_out
    let location = signedOut || example == .no_location ? nil :
        CpLocation(name: "Amazon Day 1", address: "", deviceIds: Array(1...43).map(Int64.init),
                   bounds: cpBounds(lat: 0, lon: 0))
    let offer = CpOffer(deviceId: 1, port: 1,
        charger: example == .offer_no_floor ? "SEA41-29" : "SEA41 - 29 P3",
        untilMs: example == .unknown_deadline ? 0 : Int64(now.addingTimeInterval(1_690).timeIntervalSince1970 * 1_000),
        startMs: Int64(now.addingTimeInterval(600).timeIntervalSince1970 * 1_000))
    let charging = phase == "CHARGING" ? CpCharging(sessionId: 9, powerKw: 6.6, energyKwh: 7.4,
        minutes: 65, canStop: example != .charging_no_stop, miles: 31,
        vehicle: "Tesla Model Y", charger: "SEA41 - 29 P3") : nil
    let floors = zip(["P2", "P3", "P4", "P5", "P6"], [14, 18, 22, 22, 10]).enumerated().map { index, pair in
        CpFloor(level: pair.0, free: phase == nil ? [8, 17, 22, 21, 10][index] : 0, total: pair.1)
    }
    return CpState(signedOut: signedOut,
        account: cpAccount(hasSession: !signedOut, expired: false), location: location,
        now: location == nil ? nil : CpNow(free: 78, inUse: 7, offline: 1, stations: 43),
        waitlist: phase.map { .inLine(place: $0 == "WAITING" ? 3 : nil, state: $0,
                                    stations: 43, offer: offer, auto: false) } ?? .notQueued,
        charging: charging, autoOn: auto, floors: floors, snoozesLeft: allowance)
}
