import Foundation
import CoreFoundation

/// Doors / garages / locks as Home Assistant reports them: the model shared by the guarded door
/// command path, Activity and the Alarm card's garage row. Ported from Android `DoorsState.kt`
/// (`DoorsTone` lives in Car.swift). Every garage action is a direct tap.
public enum DoorKind: String, Sendable, Equatable { case sensor, garage, lock }

public struct Door: Sendable, Equatable {
    public let id: String; public let name: String; public let kind: DoorKind; public let state: String; public let since: Date?
    /// nil is a missing legacy mask; false is explicit unsupported or malformed present telemetry.
    public let supportsStop: Bool?
    public init(id: String, name: String, kind: DoorKind, state: String, since: Date?, supportsStop: Bool? = nil) {
        self.id = id; self.name = name; self.kind = kind; self.state = state; self.since = since
        self.supportsStop = supportsStop
    }
}

public enum DoorAction: String, Codable, Sendable, Equatable {
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
