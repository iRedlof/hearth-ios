import Foundation
import CoreFoundation

/// Raw provider identity is private evidence; formatted labels/counts never identify an action.
public struct CpObservedIdentity: Codable, Sendable, Equatable {
    public let phase: String
    public let stationIDs: [Int64]
    public let token: String?
    public let deviceID: Int64?
    public let port: Int?
    public let startMs: Int64?
    public let deadlineMs: Int64?
    public let sessionID: Int64?

    public var queueKnown: Bool { phase != "UNKNOWN" }
    public var queued: Bool { queueKnown && phase != "NOT_QUEUED" }
}

public struct CpObservation: Codable, Sendable, Equatable {
    public let provider: CpProviderReading
    public let identity: CpObservedIdentity
}

/// Detail association comes from the owned request purpose, rather than whichever offer is current later.
public struct CpDetailEvidence: Sendable {
    public let allowanceToken: String?
    public let allowanceJson: String?
    public let chargingSessionID: Int64?
    public let chargingJson: String?

    public init(allowanceToken: String? = nil, allowanceJson: String? = nil,
                chargingSessionID: Int64? = nil, chargingJson: String? = nil) {
        self.allowanceToken = allowanceToken; self.allowanceJson = allowanceJson
        self.chargingSessionID = chargingSessionID; self.chargingJson = chargingJson
    }
}

public enum CpObservationError: Error, Equatable {
    case malformed, detailsChanged
}

public func cpOwnedProfile(_ json: String) throws -> (userId: Int64, email: String) {
    guard let root = cpOwnedObject(json), root["error"] == nil, root["error_message"] == nil,
          let user = root["user"] as? [String: Any], user["error"] == nil, user["error_message"] == nil,
          let id = cpOwnedInteger(user["userId"]), id > 0 else { throw CpObservationError.malformed }
    return (id, (user["email"] as? String) ?? (user["emailAddress"] as? String) ?? (user["username"] as? String) ?? "")
}

public func cpOwnedStations(_ json: String) throws -> [CpStation] {
    guard let root = cpOwnedObject(json), root["error"] == nil, root["error_message"] == nil,
          let map = root["map_data"] as? [String: Any], map["error"] == nil, map["error_message"] == nil,
          let stations = map["stations"] as? [[String: Any]] else { throw CpObservationError.malformed }
    var ids = Set<Int64>()
    for station in stations {
        guard let id = cpOwnedInteger(station["device_id"]), id > 0, ids.insert(id).inserted,
              let lat = station["lat"] as? NSNumber, CFGetTypeID(lat) != CFBooleanGetTypeID(),
              let lon = station["lon"] as? NSNumber, CFGetTypeID(lon) != CFBooleanGetTypeID(),
              lat.doubleValue.isFinite, lon.doubleValue.isFinite,
              (-90...90).contains(lat.doubleValue), (-180...180).contains(lon.doubleValue) else {
            throw CpObservationError.malformed
        }
    }
    return cpStationsFrom(json)
}

extension CpObservedIdentity {
    var valid: Bool {
        let known: Set<String> = ["UNKNOWN", "NOT_QUEUED", "WAITING", "PENDING", "ACCEPT_PENDING",
            "PENDING_PLUG_IN", "DIB_PENDING_PLUG_IN", "PASS", "CHARGING", "CHARGING_FAULT",
            "DIB_PLUG_OUT", "PENDING_PLUG_OUT", "OVER_STAYED", "BLOCKED"]
        guard known.contains(phase), stationIDs == Set(stationIDs).sorted(),
              stationIDs.allSatisfy({ $0 > 0 }), token.map({ !$0.isEmpty }) ?? true,
              deviceID.map({ $0 > 0 }) ?? true, port.map({ $0 > 0 }) ?? true,
              sessionID.map({ $0 > 0 }) ?? true,
              (startMs == nil) == (deadlineMs == nil) else { return false }
        if let startMs, let deadlineMs, startMs < 0 || deadlineMs < startMs { return false }
        if phase == "NOT_QUEUED" {
            return stationIDs.isEmpty && token == nil && deviceID == nil && port == nil && startMs == nil
        }
        return true
    }
}

extension CpObservation {
    var valid: Bool {
        guard identity.valid, provider.charging?.sessionId == identity.sessionID else { return false }
        switch provider.waitlist {
        case .notQueued: return identity.phase == "NOT_QUEUED"
        case .inLine(_, let state, _, let offer, _):
            guard state == identity.phase || (identity.phase == "UNKNOWN" && identity.sessionID != nil && state == "CHARGING") else { return false }
            if let offer {
                if identity.phase == "PASS", identity.deviceID == nil, identity.port == nil {
                    // The legacy display DTO also carries an account-wide snooze countdown.
                    // Its zero placeholders describe no assigned charger; they never grant a target.
                    return offer.deviceId == 0 && offer.port == 0 &&
                        offer.startMs == identity.startMs && offer.untilMs == identity.deadlineMs
                }
                return offer.deviceId == identity.deviceID && offer.port == identity.port &&
                    offer.startMs == identity.startMs && offer.untilMs == identity.deadlineMs
            }
            return true
        }
    }
}

public func cpOwnedObservation(statusJson: String, inlineJson: String? = nil,
                               details: CpDetailEvidence = CpDetailEvidence(),
                               availability: CpNow? = nil, floors: [CpFloor] = []) throws -> CpObservation {
    guard let root = cpOwnedObject(statusJson), root["error"] == nil, root["error_message"] == nil,
          let user = root["user_status"] as? [String: Any], user["error"] == nil, user["error_message"] == nil else {
        throw CpObservationError.malformed
    }
    if let raw = user["charging"] {
        guard let charging = raw as? [String: Any], let state = charging["state"] as? String, !state.isEmpty,
              charging["error"] == nil, charging["error_message"] == nil else { throw CpObservationError.malformed }
        if !cpSessionDone.contains(state.lowercased()) {
            guard let id = cpOwnedInteger(charging["sessionId"]), id > 0 else { throw CpObservationError.malformed }
        }
    }
    let liveCharging = user["charging"] as? [String: Any]
    let chargingFinished = liveCharging.map {
        cpSessionDone.contains(($0["state"] as? String ?? "").lowercased())
    } ?? false
    var sessionID: Int64?
    if !chargingFinished, let raw = liveCharging?["sessionId"] {
        guard let id = cpOwnedInteger(raw), id > 0 else { throw CpObservationError.malformed }
        sessionID = id
    }
    let waitlist = user["waitlist"] as? [String: Any]
    if user["waitlist"] != nil, waitlist == nil { throw CpObservationError.malformed }
    let state: [String: Any]?
    if let explicitIdle = waitlist?["state"] as? String {
        guard explicitIdle == "NOT_QUEUED" else { throw CpObservationError.malformed }
        state = ["state": explicitIdle]
    } else {
        state = waitlist?["state"] as? [String: Any]
        if waitlist?["state"] != nil, state == nil { throw CpObservationError.malformed }
    }
    guard waitlist?["error"] == nil, waitlist?["error_message"] == nil,
          state?["error"] == nil, state?["error_message"] == nil else { throw CpObservationError.malformed }
    guard let rawPhase = state?["state"] as? String, !rawPhase.isEmpty else {
        // Charging can be identified even when the provider omits its waitlist section.
        guard sessionID != nil else { throw CpObservationError.malformed }
        return try cpOwnedChargingObservation(sessionID: sessionID!, details: details,
            availability: availability, floors: floors)
    }
    let known: Set<String> = [
        "NOT_QUEUED", "WAITING", "PENDING", "ACCEPT_PENDING", "PENDING_PLUG_IN",
        "DIB_PENDING_PLUG_IN", "PASS", "CHARGING", "CHARGING_FAULT", "DIB_PLUG_OUT",
        "PENDING_PLUG_OUT", "OVER_STAYED", "BLOCKED",
    ]
    let phase = known.contains(rawPhase) ? rawPhase : "UNKNOWN"
    var stationIDs: [Int64] = []
    if let rawStations = waitlist?["stations"] {
        guard let stations = rawStations as? [[String: Any]] else { throw CpObservationError.malformed }
        for station in stations {
            guard let id = cpOwnedInteger(station["deviceId"]), id > 0 else { throw CpObservationError.malformed }
            stationIDs.append(id)
        }
    } else if phase != "NOT_QUEUED" { throw CpObservationError.malformed }
    stationIDs = Set(stationIDs).sorted()
    if let raw = state?["token"], !(raw is String) { throw CpObservationError.malformed }
    let token = (state?["token"] as? String).flatMap { $0.isEmpty ? nil : $0 }
    var deviceID: Int64?
    var port: Int?
    var startMs: Int64?
    var deadlineMs: Int64?
    if let raw = state?["deviceId"] {
        guard let id = cpOwnedInteger(raw), id > 0 else { throw CpObservationError.malformed }
        deviceID = id
    }
    if let raw = state?["portNo"] {
        guard let number = cpOwnedInteger(raw), number > 0, let value = Int(exactly: number) else {
            throw CpObservationError.malformed
        }
        port = value
    }
    if state?["startTimeUTC"] != nil || state?["duration"] != nil {
        guard let start = cpOwnedInteger(state?["startTimeUTC"]), start >= 0,
              let duration = cpOwnedInteger(state?["duration"]), duration >= 0 else {
            throw CpObservationError.malformed
        }
        let sum = start.addingReportingOverflow(duration)
        let startMillis = start.multipliedReportingOverflow(by: 1_000)
        let deadlineMillis = sum.partialValue.multipliedReportingOverflow(by: 1_000)
        guard !sum.overflow, !startMillis.overflow, !deadlineMillis.overflow else {
            throw CpObservationError.malformed
        }
        if start > 0, duration > 0 {
            startMs = startMillis.partialValue; deadlineMs = deadlineMillis.partialValue
        }
    }
    if let requested = details.allowanceToken, requested != token { throw CpObservationError.detailsChanged }
    let allowance: Int?
    if details.allowanceToken != nil, let json = details.allowanceJson, let root = cpOwnedObject(json),
       root["error"] == nil, root["error_message"] == nil, let response = root["response"] as? [String: Any],
       response["error"] == nil, response["error_message"] == nil {
        if let returned = response["token"] as? String, returned != token { throw CpObservationError.detailsChanged }
        allowance = cpOwnedInteger(response["remainingSnoozeCount"]).flatMap { $0 >= 0 ? Int(exactly: $0) : nil }
    } else { allowance = nil }
    let charging = try cpOwnedCharging(sessionID: sessionID, details: details)
    var presentation = cpWaitlistFrom(statusJson, inlineJson)
    if phase == "UNKNOWN" {
        let place: Int?
        if case let .inLine(p, _, _, _, _) = presentation { place = p } else { place = nil }
        presentation = .inLine(place: place, state: "UNKNOWN", stations: stationIDs.count, offer: nil, auto: false)
    }
    let provider = CpProviderReading(waitlist: presentation, charging: charging,
        availability: availability, floors: floors, snoozesLeft: allowance)
    // Reuse the provider DTO's finite/overflow validation before it becomes persisted evidence.
    _ = try JSONEncoder().encode(provider)
    let observation = CpObservation(provider: provider,
        identity: CpObservedIdentity(phase: phase, stationIDs: stationIDs, token: token,
            deviceID: deviceID, port: port, startMs: startMs, deadlineMs: deadlineMs, sessionID: sessionID))
    guard observation.valid else { throw CpObservationError.malformed }
    return observation
}

private func cpOwnedChargingObservation(sessionID: Int64, details: CpDetailEvidence,
                                       availability: CpNow?, floors: [CpFloor]) throws -> CpObservation {
    let provider = CpProviderReading(waitlist: .inLine(place: nil, state: "CHARGING", stations: 0, offer: nil, auto: false),
        charging: try cpOwnedCharging(sessionID: sessionID, details: details),
        availability: availability, floors: floors)
    _ = try JSONEncoder().encode(provider)
    return CpObservation(provider: provider,
        identity: CpObservedIdentity(phase: "UNKNOWN", stationIDs: [], token: nil, deviceID: nil,
            port: nil, startMs: nil, deadlineMs: nil, sessionID: sessionID))
}

private func cpOwnedCharging(sessionID: Int64?, details: CpDetailEvidence) throws -> CpCharging? {
    if let requested = details.chargingSessionID, requested != sessionID { throw CpObservationError.detailsChanged }
    guard let sessionID else { return nil }
    if details.chargingSessionID == sessionID, let json = details.chargingJson, let root = cpOwnedObject(json),
       root["error"] == nil, root["error_message"] == nil, let charging = root["charging_status"] as? [String: Any],
       charging["error"] == nil, charging["error_message"] == nil {
        guard cpOwnedInteger(charging["session_id"]) == sessionID else { throw CpObservationError.detailsChanged }
        for key in ["session_time", "charging_time"] {
            if let number = charging[key] as? NSNumber {
                let value = number.doubleValue
                guard value.isFinite, value >= 0, value / 1_000 < Double(Int.max) else {
                    throw CpObservationError.malformed
                }
            }
        }
        if let value = cpChargingFrom(json) {
            let supported = cpOwnedBoolean(charging["stop_charge_supported"]) == true
            let enabled = charging["enable_stop_charging"] == nil || cpOwnedBoolean(charging["enable_stop_charging"]) == true
            return CpCharging(sessionId: value.sessionId, powerKw: value.powerKw, energyKwh: value.energyKwh,
                minutes: value.minutes, canStop: supported && enabled, miles: value.miles, seconds: value.seconds,
                vehicle: value.vehicle, charger: value.charger)
        }
    }
    return CpCharging(sessionId: sessionID, powerKw: nil, energyKwh: nil, minutes: nil, canStop: false)
}

private func cpOwnedObject(_ json: String) -> [String: Any]? {
    (try? JSONSerialization.jsonObject(with: Data(json.utf8))) as? [String: Any]
}

private func cpOwnedInteger(_ raw: Any?) -> Int64? {
    guard let number = raw as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
    return Int64(number.stringValue)
}

private func cpOwnedBoolean(_ raw: Any?) -> Bool? {
    guard let number = raw as? NSNumber else { return nil }
    if CFGetTypeID(number) == CFBooleanGetTypeID() { return number.boolValue }
    guard let value = Int64(number.stringValue), value == 0 || value == 1 else { return nil }
    return value == 1
}
