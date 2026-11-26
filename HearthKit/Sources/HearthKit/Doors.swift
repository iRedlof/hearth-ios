import Foundation
import CoreFoundation

/// Doors / garages / locks for the Doors widget. Ported from Android `DoorsState.kt` (`DoorsTone`
/// lives in Car.swift). Every garage action is a direct tap.
public enum DoorKind: String, Sendable, Equatable { case sensor, garage, lock }

public struct Door: Sendable, Equatable {
    public let id: String; public let name: String; public let kind: DoorKind; public let state: String; public let since: Date?
    public let checkedAt: Date?; public let error: String?
    /// nil is a missing legacy mask; false is explicit unsupported or malformed present telemetry.
    public let supportsStop: Bool?
    public init(id: String, name: String, kind: DoorKind, state: String, since: Date?,
                checkedAt: Date? = nil, error: String? = nil, supportsStop: Bool? = nil) {
        self.id = id; self.name = name; self.kind = kind; self.state = state; self.since = since
        self.checkedAt = checkedAt; self.error = error
        self.supportsStop = supportsStop
    }
}

public enum DoorAction: String, Sendable, Equatable {
    case open, close, stop, lock
    public var label: String { switch self { case .open: "Open"; case .close: "Close"; case .stop: "Stop"; case .lock: "Lock" } }
    public var pending: String { switch self { case .open: "Opening…"; case .close: "Closing…"; case .stop: "Stopping…"; case .lock: "Locking…" } }
    public var service: (domain: String, service: String) {
        switch self {
        case .open: ("cover", "open_cover"); case .close: ("cover", "close_cover")
        case .stop: ("cover", "stop_cover"); case .lock: ("lock", "lock")
        }
    }
    public var needsConfirm: Bool { false }

    /// A successful Stop requires a positively known resting position.
    public func done(_ state: String?) -> Bool {
        switch self {
        case .open: state == "open"
        case .close: state == "closed"
        case .lock: state == "locked"
        case .stop: state == "open" || state == "closed"
        }
    }
}

public struct DoorView: Sendable, Equatable {
    public let id: String; public let name: String; public let status: String; public let open: Bool?; public let action: DoorAction?
    public init(id: String, name: String, status: String, open: Bool?, action: DoorAction?) {
        self.id = id; self.name = name; self.status = status; self.open = open; self.action = action
    }
}

public struct DoorsSummary: Sendable, Equatable {
    public let headline: String; public let tone: DoorsTone; public let lockLine: String?; public let rows: [DoorView]
    public init(headline: String, tone: DoorsTone, lockLine: String?, rows: [DoorView]) {
        self.headline = headline; self.tone = tone; self.lockLine = lockLine; self.rows = rows
    }
}

private let DOOR_NO_SIGNAL: Set<String> = ["unavailable", "unknown", "none", ""]

public func doorView(_ d: Door, now: Date, zone: TimeZone = .current, locale: Locale = .current) -> DoorView {
    if d.error != nil {
        let status: String
        if d.checkedAt != nil || (!DOOR_NO_SIGNAL.contains(d.state) && validDoorState(d.kind, d.state)) {
            let previous = Door(id: d.id, name: d.name, kind: d.kind, state: d.state, since: d.since,
                supportsStop: d.supportsStop)
            status = "Last known · \(doorView(previous, now: now, zone: zone, locale: locale).status)"
        } else { status = "No reading" }
        return DoorView(id: d.id, name: d.name, status: status, open: nil, action: nil)
    }
    let since = sinceLabel(d.since, now: now, zone: zone, locale: locale)
    func shut(_ word: String) -> String { [word, since].compactMap { $0 }.joined(separator: " · ") }
    func openFor() -> String { d.since.map { "Open · \(howLong(now.timeIntervalSince($0)))" } ?? "Open" }
    if DOOR_NO_SIGNAL.contains(d.state) { return DoorView(id: d.id, name: d.name, status: "No signal", open: nil, action: nil) }
    switch d.kind {
    case .sensor:
        switch d.state {
        case "off": return DoorView(id: d.id, name: d.name, status: shut("Closed"), open: false, action: nil)
        case "on": return DoorView(id: d.id, name: d.name, status: openFor(), open: true, action: nil)
        default: return DoorView(id: d.id, name: d.name, status: d.state, open: nil, action: nil)
        }
    case .garage:
        switch d.state {
        case "closed": return DoorView(id: d.id, name: d.name, status: shut("Closed"), open: false, action: .open)
        case "open": return DoorView(id: d.id, name: d.name, status: openFor(), open: true, action: .close)
        case "opening": return DoorView(id: d.id, name: d.name, status: "Opening…", open: true, action: .stop)
        case "closing": return DoorView(id: d.id, name: d.name, status: "Closing…", open: true, action: .stop)
        default: return DoorView(id: d.id, name: d.name, status: d.state, open: nil, action: nil)
        }
    case .lock:
        let v = lockStatusFor(d.state)
        switch d.state {
        case "locked": return DoorView(id: d.id, name: d.name, status: shut("Locked"), open: false, action: nil)
        case "unlocked", "open":
            let sincePart = since.map { $0.hasPrefix("since ") ? String($0.dropFirst(6)) : $0 }
            return DoorView(id: d.id, name: d.name, status: [v.title, sincePart].compactMap { $0 }.joined(separator: " · "),
                            open: true, action: .lock)
        default: return DoorView(id: d.id, name: d.name, status: v.title, open: v.secure.map { !$0 }, action: nil)
        }
    }
}

/// "3 min", "2 h 5 min", "1 day 3 h".
public func howLong(_ interval: TimeInterval) -> String {
    let m = max(0, Int(interval / 60))
    switch m {
    case ..<1: return "just now"
    case ..<60: return "\(m) min"
    case ..<(24 * 60):
        let s = "\(m / 60) h \(m % 60) min"
        return s.hasSuffix(" 0 min") ? String(s.dropLast(6)) : s
    default:
        let s = "\(m / (24 * 60)) day\(m >= 48 * 60 ? "s" : "") \((m / 60) % 24) h"
        return s.hasSuffix(" 0 h") ? String(s.dropLast(4)) : s
    }
}

public func doorsSummary(_ doors: [Door], now: Date, zone: TimeZone = .current, locale: Locale = .current) -> DoorsSummary {
    let views = doors.map { ($0, doorView($0, now: now, zone: zone, locale: locale)) }
    let notShut = views.filter { $0.1.open == true }
    let silent = views.filter { $0.1.open == nil }
    let lock = views.first { $0.0.kind == .lock }
    let lockLine: String? = lock.flatMap { (d, v) in v.open == false ? "\(d.name) locked" : nil }
    let unlocked = notShut.filter { $0.0.kind == .lock }
    let open = notShut.filter { $0.0.kind != .lock }
    let openPart: String?
    if open.count == 1 {
        let (d, v) = open[0]
        openPart = v.status.hasSuffix("…") ? "\(d.name) \(v.status.lowercased())" : "\(d.name) open"
    } else if open.count > 1 { openPart = "\(open.count) open" } else { openPart = nil }
    let lockPart = unlocked.first?.1.status.components(separatedBy: " ·").first?.lowercased()
    let headline: String
    if let openPart, let lockPart { headline = "\(openPart) · \(lockPart)" }
    else if let openPart { headline = openPart }
    else if let lockPart { headline = "\(unlocked.first!.0.name) \(lockPart)" }
    else if !silent.isEmpty { headline = "\(silent.count) not reporting" }
    else if doors.isEmpty { headline = "No doors chosen" }
    else { headline = "All shut" }
    let forgotten = open.contains { (d, _) in d.since.map { now.timeIntervalSince($0) >= 30 * 60 } ?? false }
    let tone: DoorsTone = forgotten ? .alert
        : (!notShut.isEmpty ? .warn : ((!silent.isEmpty || doors.isEmpty) ? .unknown : .calm))
    let rows = (notShut + silent + views.filter { $0.1.open == false }).map { $0.1 }
    return DoorsSummary(headline: headline, tone: tone, lockLine: lockLine, rows: rows)
}

/// "Main Door Sensor" → "Main Door"; garage and gate friendly names remain distinguishable.
public func doorName(_ friendly: String, _ kind: DoorKind) -> String {
    (kind == .sensor && friendly.hasSuffix(" Sensor") ? String(friendly.dropLast(7)) : friendly)
        .trimmingCharacters(in: .whitespacesAndNewlines)
}

/// A door from its `GET /api/states/<id>` body (nil if not a door Hearth shows).
public func doorFromState(_ json: String) -> Door? {
    guard let data = json.data(using: .utf8),
          let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let id = obj["entity_id"] as? String, let kind = doorKindForID(id),
          isDoorEligibleObject(obj), let state = obj["state"] as? String,
          validDoorState(kind, state) else { return nil }
    let friendly = (obj["attributes"] as? [String: Any])?["friendly_name"] as? String
    let supportsStop: Bool?
    if kind == .garage, let attributes = obj["attributes"] as? [String: Any],
       let raw = attributes["supported_features"] {
        if let number = raw as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() {
            let value = number.doubleValue
            supportsStop = value.isFinite && value >= 0 && value < Double(Int.max) &&
                value.rounded(.towardZero) == value && (Int(value) & 8 != 0)
        } else { supportsStop = false }
    } else { supportsStop = nil }
    return Door(id: id, name: doorName(friendly?.isEmpty == false ? friendly! : id, kind),
                kind: kind, state: state, since: parseOffsetDateTime(obj["last_changed"] as? String),
                supportsStop: supportsStop)
}
