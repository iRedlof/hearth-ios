import Foundation

// MARK: - Forgiving JSON access (mirrors Android's org.json opt* semantics)

private func asObject(_ any: Any?) -> [String: Any]? { any as? [String: Any] }
private func asArray(_ any: Any?) -> [Any]? { any as? [Any] }
private func parse(_ json: String?) -> Any? {
    guard let s = json, let d = s.data(using: .utf8) else { return nil }
    return try? JSONSerialization.jsonObject(with: d, options: [.fragmentsAllowed])
}
private func optString(_ d: [String: Any]?, _ k: String) -> String {
    if let s = d?[k] as? String { return s }
    if let n = d?[k] as? NSNumber { return n.stringValue }
    return ""
}
private func optDoubleFinite(_ d: [String: Any]?, _ k: String) -> Double? {
    guard let v = d?[k] else { return nil }
    let x: Double?
    if let n = v as? NSNumber { x = n.doubleValue } else if let s = v as? String { x = Double(s) } else { x = nil }
    guard let x, x.isFinite else { return nil }
    return x
}
private func optLong(_ d: [String: Any]?, _ k: String) -> Int64 {
    if let n = d?[k] as? NSNumber { return n.int64Value }
    if let s = d?[k] as? String, let v = Int64(s) { return v }
    return 0
}
private func optInt(_ d: [String: Any]?, _ k: String) -> Int {
    if let n = d?[k] as? NSNumber { return n.intValue }
    if let s = d?[k] as? String, let v = Int(s) { return v }
    return 0
}
private func optBool(_ d: [String: Any]?, _ k: String) -> Bool { (d?[k] as? NSNumber)?.boolValue ?? (d?[k] as? Bool ?? false) }

// MARK: - Model (ChargePointState.kt)

public struct CpBounds: Sendable, Equatable, Codable {
    public let swLat, swLon, neLat, neLon: Double
}

/// A station as the map reply has it: where, its ports by state, whether it takes the waitlist.
public struct CpStation: Sendable, Equatable {
    public let deviceId: Int64
    public let address: String
    public let name: String
    public let lat, lon: Double
    public let site: String
    public let free, inUse, offline: Int
    public let waitlist: Bool
    public let city, state, level: String
}

/// A location: every station at one address, its area + name (the site code like "SEA41", else the address).
public struct CpLocation: Sendable, Equatable, Codable {
    public let name: String
    public let address: String
    public let deviceIds: [Int64]
    public let bounds: CpBounds
    public let city: String
    public let state: String
    public let label: String
    public init(name: String, address: String, deviceIds: [Int64], bounds: CpBounds, city: String = "", state: String = "", label: String = "") {
        self.name = name; self.address = address; self.deviceIds = deviceIds; self.bounds = bounds
        self.city = city; self.state = state; self.label = label
    }
    /// What the card calls it: your name, else ChargePoint's.
    public var title: String { label.isEmpty ? name : label }
    public var fullAddress: String { [address, city, state].filter { !$0.isEmpty }.joined(separator: ", ") }
}

/// A location's ports now.
public struct CpNow: Sendable, Equatable {
    public let free, inUse, offline, stations: Int
    public var total: Int { free + inUse + offline }
    public init(free: Int, inUse: Int, offline: Int, stations: Int) {
        self.free = free; self.inUse = inUse; self.offline = offline; self.stations = stations
    }
}

/// The charger offered (or held): which (0 = none/snoozed), and until when (start + duration).
public struct CpOffer: Sendable, Equatable {
    public let deviceId: Int64
    public let port: Int
    public let charger: String
    public let untilMs: Int64
    public let startMs: Int64
    public init(deviceId: Int64, port: Int, charger: String, untilMs: Int64, startMs: Int64 = 0) {
        self.deviceId = deviceId; self.port = port; self.charger = charger; self.untilMs = untilMs; self.startMs = startMs
    }
}

/// Where you are with the waitlist.
public enum CpWaitlist: Sendable, Equatable {
    case notQueued
    case inLine(place: Int?, state: String, stations: Int, offer: CpOffer?, auto: Bool)
}

/// A charging session's numbers (python-chargepoint's `charging_status`; its times are milliseconds).
public struct CpCharging: Sendable, Equatable {
    public let sessionId: Int64
    public let powerKw: Double?
    public let energyKwh: Double?
    public let minutes: Int?
    public let canStop: Bool
    public let miles: Double?
    public let seconds: Int?
    public let vehicle: String?
    public let charger: String?
    public init(sessionId: Int64, powerKw: Double?, energyKwh: Double?, minutes: Int?, canStop: Bool,
                miles: Double? = nil, seconds: Int? = nil, vehicle: String? = nil, charger: String? = nil) {
        self.sessionId = sessionId; self.powerKw = powerKw; self.energyKwh = energyKwh; self.minutes = minutes
        self.canStop = canStop; self.miles = miles; self.seconds = seconds; self.vehicle = vehicle; self.charger = charger
    }
}

// MARK: - Pure functions

private func portState(_ s: String) -> Int {
    switch s.lowercased() {
    case "available": return 0
    case "in_use", "inuse", "charging", "occupied", "busy", "waitlist_reserved", "reserved": return 1
    default: return 2
    }
}

private let siteRegex = try! NSRegularExpression(pattern: "\\b([A-Z]{2,}\\d{1,4})\\b")
private func siteOf(_ name1: String, _ name2: String) -> String {
    for s in [name1, name2] {
        let r = NSRange(s.startIndex..., in: s)
        if let m = siteRegex.firstMatch(in: s, range: r), let rr = Range(m.range(at: 1), in: s) {
            return String(s[rr])
        }
    }
    return ""
}

private let levelRegex = try! NSRegularExpression(pattern: "\\bP\\d{1,2}\\b")
/// The level in a charger's name ("SEA41 - 29 P3" -> "P3").
public func cpLevelOf(_ name: String) -> String? {
    let r = NSRange(name.startIndex..., in: name)
    guard let m = levelRegex.firstMatch(in: name, range: r), let rr = Range(m.range, in: name) else { return nil }
    return String(name[rr])
}

/// The stations in the map reply (`map_data.stations`).
public func cpStationsFrom(_ json: String?) -> [CpStation] {
    guard let root = asObject(parse(json)),
          let mapData = asObject(root["map_data"]),
          let stations = asArray(mapData["stations"]) else { return [] }
    return stations.compactMap { asObject($0) }.map { s in
        let ports = asArray(s["ports"]) ?? []
        let states = ports.compactMap { asObject($0) }.map { p -> Int in
            let status = (p["status_v2"] as? String) ?? (p["status"] as? String) ?? ""
            return portState(status)
        }
        let name1 = optString(s, "name1"), name2 = optString(s, "name2")
        let levelLabel = optString(s, "parking_label")
        let level = (cpLevelOf(levelLabel) == levelLabel && !levelLabel.isEmpty) ? levelLabel : (cpLevelOf(name2) ?? "")
        return CpStation(
            deviceId: optLong(s, "device_id"),
            address: optString(s, "address1"),
            name: name2.isEmpty ? name1 : name2,
            lat: optDoubleFinite(s, "lat") ?? 0, lon: optDoubleFinite(s, "lon") ?? 0,
            site: siteOf(name1, name2),
            free: states.filter { $0 == 0 }.count,
            inUse: states.filter { $0 == 1 }.count,
            offline: states.filter { $0 == 2 }.count,
            waitlist: optBool(s, "waitlist_allowed"),
            city: optString(s, "city"), state: optString(s, "state_name"), level: level)
    }
}

/// Stations grouped into locations, biggest first: by site code, else address.
public func cpLocations(_ stations: [CpStation]) -> [CpLocation] {
    let groups = Dictionary(grouping: stations) { $0.site.isEmpty ? "@" + $0.address : $0.site }
    let pad = 0.0004
    let locations = groups.map { (key, s) -> CpLocation in
        let address = Dictionary(grouping: s, by: { $0.address }).max { $0.value.count < $1.value.count }!.key
        let name = key.hasPrefix("@") ? address : key
        let at = s.filter { $0.address == address }
        return CpLocation(
            name: name, address: address,
            deviceIds: s.map { $0.deviceId }.sorted(),
            bounds: CpBounds(swLat: s.map { $0.lat }.min()! - pad, swLon: s.map { $0.lon }.min()! - pad,
                             neLat: s.map { $0.lat }.max()! + pad, neLon: s.map { $0.lon }.max()! + pad),
            city: at.first { !$0.city.isEmpty }?.city ?? "",
            state: at.first { !$0.state.isEmpty }?.state ?? "")
    }
    return locations.sorted { $0.deviceIds.count > $1.deviceIds.count }
}

/// The location's ports now, from a map reply (its own stations only).
public func cpLocationNow(_ loc: CpLocation, _ stations: [CpStation]) -> CpNow {
    let ids = Set(loc.deviceIds)
    let mine = stations.filter { ids.contains($0.deviceId) }
    return CpNow(free: mine.reduce(0) { $0 + $1.free }, inUse: mine.reduce(0) { $0 + $1.inUse },
                 offline: mine.reduce(0) { $0 + $1.offline }, stations: mine.count)
}

/// "SEA41 SEA41-29 P3" (site, then charger) -> "SEA41-29 P3".
private func chargerName(_ name: String) -> String {
    let parts = name.trimmingCharacters(in: .whitespaces).split(separator: " ", maxSplits: 1).map(String.init)
    if parts.count == 2, parts[1].hasPrefix(parts[0]) { return parts[1] }
    return name.trimmingCharacters(in: .whitespaces)
}

private func offerFrom(_ st: [String: Any], _ stations: [Any]?) -> CpOffer? {
    let id = optLong(st, "deviceId")
    let start = optLong(st, "startTimeUTC")
    let duration = optLong(st, "duration")
    if id <= 0 && (start <= 0 || duration <= 0) { return nil }
    var name = ""
    if id > 0, let stations {
        name = stations.compactMap { asObject($0) }.first { optLong($0, "deviceId") == id }.map { optString($0, "name") } ?? ""
    }
    return CpOffer(deviceId: id, port: optInt(st, "portNo"), charger: chargerName(name),
                   untilMs: (start > 0 && duration > 0) ? (start + duration) * 1000 : 0, startMs: start * 1000)
}

/// Your waitlist state, from your status + (in line) your place.
public func cpWaitlistFrom(_ statusJson: String?, _ inlineJson: String?) -> CpWaitlist {
    guard let root = asObject(parse(statusJson)),
          let userStatus = asObject(root["user_status"]),
          let waitlist = asObject(userStatus["waitlist"]) else { return .notQueued }
    let stateObj = asObject(waitlist["state"])
    let state = optString(stateObj, "state")
    if state.isEmpty || state.caseInsensitiveCompare("NOT_QUEUED") == .orderedSame { return .notQueued }
    var place: Int? = nil
    if let inlineObj = asObject(parse(inlineJson)) {
        let p = optInt(inlineObj, "positionInline")
        place = p > 0 ? p : nil
    }
    let stations = asArray(waitlist["stations"])
    return .inLine(place: place, state: state, stations: stations?.count ?? 0,
                   offer: stateObj.flatMap { offerFrom($0, stations) },
                   auto: optBool(stateObj, "autoSnooze"))
}

/// The offer's token (what answering it is sent with); none unless a charger is offered.
public func cpOfferToken(_ statusJson: String?) -> String? {
    guard let root = asObject(parse(statusJson)),
          let us = asObject(root["user_status"]),
          let wl = asObject(us["waitlist"]),
          let st = asObject(wl["state"]) else { return nil }
    let t = optString(st, "token")
    return t.isEmpty ? nil : t
}

/// States ChargePoint leaves on a finished session — treat as not charging.
let cpSessionDone: Set<String> = ["fully_charged", "charging_complete", "complete", "completed", "done", "finished"]

/// Your charging session's id — only while still live (a lingering `fully_charged` session is not charging).
public func cpSessionId(_ statusJson: String?) -> Int64? {
    guard let root = asObject(parse(statusJson)),
          let us = asObject(root["user_status"]),
          let charging = asObject(us["charging"]) else { return nil }
    if cpSessionDone.contains(optString(charging, "state").lowercased()) { return nil }
    let id = optLong(charging, "sessionId")
    return id > 0 ? id : nil
}

/// A session's numbers from ChargePoint's session details (`charging_status`); error/no reply -> nil.
public func cpChargingFrom(_ detailJson: String?) -> CpCharging? {
    guard let root = asObject(parse(detailJson)), let c = asObject(root["charging_status"]) else { return nil }
    if c["error_message"] != nil || c["error"] != nil { return nil }
    let seconds = (optDoubleFinite(c, "session_time") ?? optDoubleFinite(c, "charging_time")).map { Int($0 / 1000) }
    var vehicle: String? = nil
    if let v = asObject(c["vehicle_info"]) {
        let s = [optString(v, "make"), optString(v, "model")].filter { !$0.isEmpty }.joined(separator: " ")
        vehicle = s.isEmpty ? nil : s
    }
    let device = optString(c, "device_name")
    return CpCharging(
        sessionId: optLong(c, "session_id"),
        powerKw: optDoubleFinite(c, "power_kw"),
        energyKwh: optDoubleFinite(c, "energy_kwh"),
        minutes: seconds.map { $0 / 60 },
        canStop: optBool(c, "stop_charge_supported") && ((c["enable_stop_charging"] as? NSNumber)?.boolValue ?? true),
        miles: optDoubleFinite(c, "miles_added"),
        seconds: seconds,
        vehicle: vehicle,
        charger: device.isEmpty ? nil : device)
}

/// A charger's short name ("SEA41 - 29 P3" -> "SEA41-29"), without the level.
public func cpChargerShort(_ name: String) -> String {
    var s = name
    if let r = name.range(of: "\\bP\\d{1,2}\\b", options: .regularExpression) { s.removeSubrange(r) }
    return s.replacingOccurrences(of: "\\s*-\\s*", with: "-", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
}

/// "No snoozes" / "1 snooze left" / "2 snoozes left".
public func cpSnoozeLabel(_ n: Int) -> String { n == 0 ? "No snoozes" : "\(n) snooze\(n == 1 ? "" : "s") left" }

// MARK: - Account row (signed-in / signed-out honesty, v1.4.22)

public struct CpAccount: Sendable, Equatable {
    public let text: String
    public let signedIn: Bool
    public let needsReauth: Bool
    public init(text: String, signedIn: Bool, needsReauth: Bool = false) {
        self.text = text; self.signedIn = signedIn; self.needsReauth = needsReauth
    }
}

public func cpAccount(hasSession: Bool, expired: Bool, joinExpired: Bool = false) -> CpAccount {
    switch true {
    case !hasSession: return CpAccount(text: "Not signed in: ChargePoint's own login page", signedIn: false)
    case expired: return CpAccount(text: "Signed out by ChargePoint: sign in again", signedIn: false)
    case joinExpired: return CpAccount(text: "Sign in again to join & see charging", signedIn: true, needsReauth: true)
    default: return CpAccount(text: "Signed in · Join & charging expire ~2h after sign-in", signedIn: true)
    }
}
