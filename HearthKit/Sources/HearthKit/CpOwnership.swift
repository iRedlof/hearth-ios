import Foundation

/// Coherent local ownership. Provider labels and the run's historical timestamp are not identities.
public struct CpContextStamp: Codable, Sendable, Equatable {
    public let accountGeneration: String
    public let selectionRevision: String
    public let runID: String
    public let modeRevision: String
    public let settingsRevision: String
}

/// Captured when a Settings or setup surface is rendered, before asynchronous work begins.
public struct CpSettingsOrigin: Codable, Sendable, Equatable {
    public let context: CpContextStamp
    public init(context: CpContextStamp) { self.context = context }
}

public struct CpSignInOwner: Codable, Sendable, Equatable {
    public let accountGeneration: String
    public let attemptID: String
}

public struct CpReadOwner: Codable, Sendable, Equatable {
    public let accountGeneration: String
    public let selectionRevision: String
    public let readID: String
    public let startedAt: Date
    public let expiresAt: Date
}

/// Provider evidence only. Local account, building, mode and history come from the coherent store.
/// These values describe a reading; they do not authorize a provider command.
public struct CpProviderReading: Codable, Sendable, Equatable {
    public let waitlist: CpWaitlist
    public let charging: CpCharging?
    public let availability: CpNow?
    public let floors: [CpFloor]
    public let snoozesLeft: Int?

    public init(waitlist: CpWaitlist = .notQueued, charging: CpCharging? = nil,
                availability: CpNow? = nil, floors: [CpFloor] = [], snoozesLeft: Int? = nil) {
        self.waitlist = waitlist; self.charging = charging; self.availability = availability
        self.floors = floors; self.snoozesLeft = snoozesLeft
    }

    private enum CodingKeys: String, CodingKey { case waitlist, charging, availability, floors, snoozesLeft }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        waitlist = try values.decode(WaitlistWire.self, forKey: .waitlist).value()
        charging = try values.decodeIfPresent(ChargingWire.self, forKey: .charging)?.value
        availability = try values.decodeIfPresent(AvailabilityWire.self, forKey: .availability)?.value
        floors = try values.decode([CpFloor].self, forKey: .floors)
        snoozesLeft = try values.decodeIfPresent(Int.self, forKey: .snoozesLeft)
        guard valid else { throw CpStateStoreError.corrupt }
    }

    public func encode(to encoder: Encoder) throws {
        guard valid else { throw CpStateStoreError.corrupt }
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(WaitlistWire(waitlist), forKey: .waitlist)
        try values.encodeIfPresent(charging.map(ChargingWire.init), forKey: .charging)
        try values.encodeIfPresent(availability.map(AvailabilityWire.init), forKey: .availability)
        try values.encode(floors, forKey: .floors)
        try values.encodeIfPresent(snoozesLeft, forKey: .snoozesLeft)
    }

    private var valid: Bool {
        if let snoozesLeft, snoozesLeft < 0 { return false }
        if let availability {
            guard availability.free >= 0, availability.inUse >= 0, availability.offline >= 0,
                  availability.stations >= 0 else { return false }
            let occupied = availability.free.addingReportingOverflow(availability.inUse)
            let total = occupied.partialValue.addingReportingOverflow(availability.offline)
            guard !occupied.overflow, !total.overflow else { return false }
        }
        if floors.contains(where: { $0.level.isEmpty || $0.free < 0 || $0.total < $0.free }) { return false }
        if case let .inLine(place, state, stations, offer, _) = waitlist {
            guard place.map({ $0 > 0 }) ?? true, !state.isEmpty, stations >= 0 else { return false }
            if let offer {
                guard offer.deviceId >= 0, offer.port >= 0, offer.startMs >= 0, offer.untilMs >= 0 else { return false }
            }
        }
        if let charging {
            guard charging.sessionId > 0,
                  [charging.powerKw, charging.energyKwh, charging.miles].allSatisfy({
                      $0.map { $0.isFinite && $0 >= 0 } ?? true
                  }),
                  [charging.minutes, charging.seconds].allSatisfy({ $0.map { $0 >= 0 } ?? true }) else { return false }
            // The existing pure display mapper converts miles to Int and fallback minutes to seconds.
            if let miles = charging.miles, miles >= Double(Int.max) { return false }
            if charging.seconds == nil, let minutes = charging.minutes, minutes > Int.max / 60 { return false }
        }
        return true
    }

    private struct OfferWire: Codable {
        let deviceId: Int64
        let port: Int
        let charger: String
        let untilMs: Int64
        let startMs: Int64
        init(_ value: CpOffer) {
            deviceId = value.deviceId; port = value.port; charger = value.charger
            untilMs = value.untilMs; startMs = value.startMs
        }
        var value: CpOffer {
            CpOffer(deviceId: deviceId, port: port, charger: charger, untilMs: untilMs, startMs: startMs)
        }
    }

    private struct WaitlistWire: Codable {
        enum Kind: String, Codable { case notQueued, inLine }
        let kind: Kind
        let place: Int?
        let state: String?
        let stations: Int?
        let offer: OfferWire?
        let auto: Bool?
        init(_ value: CpWaitlist) {
            switch value {
            case .notQueued:
                kind = .notQueued; place = nil; state = nil; stations = nil; offer = nil; auto = nil
            case let .inLine(place, state, stations, offer, auto):
                kind = .inLine; self.place = place; self.state = state; self.stations = stations
                self.offer = offer.map(OfferWire.init); self.auto = auto
            }
        }
        func value() throws -> CpWaitlist {
            switch kind {
            case .notQueued:
                guard place == nil, state == nil, stations == nil, offer == nil, auto == nil else {
                    throw CpStateStoreError.corrupt
                }
                return .notQueued
            case .inLine:
                guard let state, let stations, let auto else { throw CpStateStoreError.corrupt }
                return .inLine(place: place, state: state, stations: stations, offer: offer?.value, auto: auto)
            }
        }
    }

    private struct AvailabilityWire: Codable {
        let free, inUse, offline, stations: Int
        init(_ value: CpNow) {
            free = value.free; inUse = value.inUse; offline = value.offline; stations = value.stations
        }
        var value: CpNow { CpNow(free: free, inUse: inUse, offline: offline, stations: stations) }
    }

    private struct ChargingWire: Codable {
        let sessionId: Int64
        let powerKw, energyKwh, miles: Double?
        let minutes, seconds: Int?
        let canStop: Bool
        let vehicle, charger: String?
        init(_ value: CpCharging) {
            sessionId = value.sessionId; powerKw = value.powerKw; energyKwh = value.energyKwh
            miles = value.miles; minutes = value.minutes; seconds = value.seconds
            canStop = value.canStop; vehicle = value.vehicle; charger = value.charger
        }
        var value: CpCharging {
            CpCharging(sessionId: sessionId, powerKw: powerKw, energyKwh: energyKwh, minutes: minutes,
                canStop: canStop, miles: miles, seconds: seconds, vehicle: vehicle, charger: charger)
        }
    }
}

public struct CpStoredReading: Codable, Sendable, Equatable {
    public let provider: CpProviderReading
    public let observedAt: Date
}

public struct CpStateFailure: Codable, Sendable, Equatable {
    public let message: String
    public let attemptedAt: Date
}

public enum CpAlertPreference: String, Codable, Sendable {
    case offer, accepted, snoozed, second
}

/// Enabling Auto requires the later owned command runtime; this foundation cannot arm it.
public enum CpStoreEdit: Sendable {
    case location(CpLocation?)
    case locationName(String)
    case signOut
    case pause
    case alert(CpAlertPreference, Bool)
}

/// A one-time import value; the App Group adapter will decode legacy defaults at its boundary.
public struct CpLegacyState: Sendable {
    public let session: CpSession?
    public let location: CpLocation?
    public let runWire: String
    public let alerts: CpAlertPrefs
    public let udid: String?
    public let pendingOperation: CpOperation?

    public init(session: CpSession? = nil, location: CpLocation? = nil, runWire: String = "",
                alerts: CpAlertPrefs = CpAlertPrefs(), udid: String? = nil, pendingOperation: CpOperation? = nil) {
        self.session = session; self.location = location; self.runWire = runWire
        self.alerts = alerts; self.udid = udid
        self.pendingOperation = pendingOperation
    }
}

/// Secret-bearing runtime context. It must not be encoded into a rendered action or proof log.
public struct CpStoreSnapshot: Sendable, Equatable {
    public let session: CpSession
    public let location: CpLocation?
    public let run: CpRun
    public let alerts: CpAlertPrefs
    public let udid: String
    public let context: CpContextStamp
    public let reading: CpStoredReading?
    public let failure: CpStateFailure?
    public let activeRead: CpReadOwner?
    public var renderedOrigin: CpRenderedOrigin? = nil
    public var operation: CpOwnedOperation? = nil
    public var ownershipFeedback: CpFeedback? = nil
    public var providerActionable: Bool? = nil

    public var settingsOrigin: CpSettingsOrigin { CpSettingsOrigin(context: context) }

    /// Without a reading, notQueued is only the existing setup projection, not proof of an empty queue.
    /// Display projection below suppresses provider Join/Resume until an owned reading exists.
    public var viewState: CpState {
        get throws {
            let provider = reading?.provider
            return CpState(signedOut: !session.isSignedIn,
                account: cpAccount(hasSession: session.userId > 0 && !session.token.isEmpty,
                    expired: session.expired, joinExpired: session.joinExpired),
                location: location, now: provider?.availability, waitlist: provider?.waitlist ?? .notQueued,
                charging: provider?.charging, autoOn: run.armed,
                floors: provider?.floors ?? [], snoozesLeft: provider?.snoozesLeft)
        }
    }

    public func displaySnapshot(now: Date = .now) throws -> CpSnapshot {
        guard now.timeIntervalSinceReferenceDate.isFinite else { throw CpStateStoreError.invalidClock }
        var display = cpSnapshot(try viewState, email: session.email,
            checkedAt: reading.map { cpClockString($0.observedAt) } ?? "—", now: now)
        display.autoWaitingForSignIn = run.armed && (!session.isSignedIn || session.joinExpired)
        if display.autoWaitingForSignIn == true {
            let reason = session.expired || session.joinExpired ? "Session expired" : "Sign in required"
            display.sub = "\(reason)\nAuto waiting"
            display.statusDescription = "\(reason). Auto waiting."
        }
        if run.snoozeUsed, case let .inLine(_, phase, _, offer?, _) = reading?.provider.waitlist,
           phase == "ACCEPT_PENDING" || CP_HELD.contains(phase),
           offer.untilMs > 0, Double(offer.untilMs) > now.timeIntervalSince1970 * 1_000 {
            // Local completed history can be newer than retained provider allowance evidence.
            display.railNotes = [display.bigAnswer, "Snooze used"]
        }
        if reading == nil, session.isSignedIn, !session.joinExpired, location != nil {
            display.actionLabel = "Open"
            display.showOpen = false
            display.keys = []
            display.autoControl = run.armed ? .stop : .disabled
        }
        if failure != nil {
            display.stale = true
            display.sub = "Couldn't check · Refresh to retry"
            display.statusDescription = "Couldn't check. Refresh to retry."
        }
        if session.isSignedIn, !session.joinExpired,
           providerActionable != nil, reading?.provider.charging == nil,
           case .inLine(_, let phase, _, let offer?, _) = reading?.provider.waitlist,
           offer.untilMs > 0, Double(offer.untilMs) <= now.timeIntervalSince1970 * 1_000 {
            if !["ACCEPT_PENDING", "PENDING_PLUG_IN", "DIB_PENDING_PLUG_IN", "PASS"].contains(phase) {
                display.deadline = nil; display.goTo = nil; display.keys = []
                display.bigAnswer = "—"; display.unit = ""
                display.railNotes = []; display.sub = "Time\nelapsed"
                display.statusDescription = "Time elapsed. Refresh to check."
                if !run.armed { display.autoControl = .disabled }
            }
        }
        let timedCleanup: Bool
        if case let .inLine(_, phase, _, offer, _) = reading?.provider.waitlist {
            let future = offer.map {
                $0.untilMs > 0 && Double($0.untilMs) > now.timeIntervalSince1970 * 1_000
            } ?? false
            timedCleanup = ["ACCEPT_PENDING", "PENDING_PLUG_IN", "DIB_PENDING_PLUG_IN", "PASS"].contains(phase) &&
                reading?.provider.charging == nil && !future
        } else { timedCleanup = false }
        if providerActionable == false || operation != nil ||
            (timedCleanup && (providerActionable != true || renderedOrigin?.observationID == nil ||
                              failure != nil || ownershipFeedback != nil)) {
            display.keys = []
            if display.actionLabel == "Join" { display.actionLabel = "Open"; display.showOpen = false }
            if !run.armed, session.isSignedIn { display.autoControl = .disabled }
        }
        if let operation {
            display.working = operation.stage != .uncertain
            if operation.stage == .uncertain {
                display.sub = CpFeedback.noResponse.caption
                display.statusDescription = CpFeedback.noResponse.message
            } else if operation.stage == .claimed || operation.stage == .preflighted {
                display.sub = "Waiting\nto send"
                display.statusDescription = "Waiting to send \(operation.action.rawValue)."
            } else {
                let labels: [CpOwnedAction: String] = [.join: "Joining…", .accept: "Accepting…", .snooze: "Snoozing…",
                    .unsnooze: "Rejoining…", .leave: "Leaving…", .stop: "Stopping…", .still: "Answering…", .done: "Answering…"]
                display.sub = labels[operation.action] ?? "Working…"
                display.statusDescription = display.sub
            }
            display.railNotes = []
        } else if let ownershipFeedback {
            display.sub = ownershipFeedback.caption
            display.statusDescription = ownershipFeedback.message
            display.railNotes = []
            if ownershipFeedback == .offerChanged || ownershipFeedback == .sessionChanged {
                display.deadline = nil; display.goTo = nil; display.stats = []
                display.bigAnswer = "—"; display.unit = ""; display.stale = true
            }
        }
        // Chosen local mode stays visible and pausable regardless of provider readiness/content.
        if run.armed {
            display.autoOn = true
            display.autoControl = .stop
        }
        display.origin = renderedOrigin
        return display
    }

    /// Only display values leave this transient secret-bearing owned capture.
    public func timelineDisplays(now: Date = .now) throws -> [CpTimelineDisplay] {
        let current = try displaySnapshot(now: now)
        var displays = [CpTimelineDisplay(date: now, snapshot: current)]
        guard session.isSignedIn, !session.joinExpired, location != nil,
              providerActionable == true, let origin = renderedOrigin,
              origin.context == context, origin.observationID != nil,
              failure == nil, operation == nil, ownershipFeedback == nil, activeRead == nil,
              reading?.provider.charging == nil,
              case let .inLine(_, phase, _, offer?, _) = reading?.provider.waitlist,
              ["ACCEPT_PENDING", "PENDING_PLUG_IN", "DIB_PENDING_PLUG_IN", "PASS"].contains(phase),
              offer.untilMs > 0 else { return displays }
        let deadline = Date(timeIntervalSince1970: Double(offer.untilMs) / 1_000)
        guard deadline.timeIntervalSinceReferenceDate.isFinite, deadline > now,
              current.deadline == deadline else { return displays }
        displays.append(CpTimelineDisplay(date: deadline, snapshot: try displaySnapshot(now: deadline)))
        return displays
    }
}

public struct CpTimelineDisplay: Sendable, Equatable {
    public let date: Date
    public let snapshot: CpSnapshot
    public init(date: Date, snapshot: CpSnapshot) {
        self.date = date; self.snapshot = snapshot
    }
}

public enum CpStateStoreError: Error, Equatable {
    case invalidClock
    case corrupt
    case unsupportedVersion
    case missingAuthoritativeState
    case ownershipUnavailable
}
