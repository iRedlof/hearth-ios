import Foundation

/// Illustrative gallery conditions, with no session or provider authority.
public enum CpWidgetPreviewExample: String, CaseIterable, Identifiable, Sendable {
    case heldSnoozeAvailable
    case heldNoSnoozes
    case sessionExpiredSignInRequired

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .heldSnoozeAvailable: "Spot held · snooze available"
        case .heldNoSnoozes: "Spot held · no snoozes left"
        case .sessionExpiredSignInRequired: "Session expired · sign in required"
        }
    }
}

/// `now` is the retained gallery-visit reference, not a replacement for the live countdown clock.
public func cpWidgetPreviewState(_ example: CpWidgetPreviewExample, now: Date) -> CpState {
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
