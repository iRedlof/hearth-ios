import Foundation
import CoreFoundation

/// The alarm as Home Assistant reports it (`alarm_control_panel.*`). Ported from Android `AlarmState.kt`.
public struct AlarmState: Sendable, Equatable {
    public let state: String
    public let lastChanged: Date?
    public let entityID: String?
    public let supportedFeatures: Int?
    public let codeFormat: String?
    public let codeArmRequired: Bool?
    public init(state: String, lastChanged: Date?, entityID: String? = nil,
                supportedFeatures: Int? = nil, codeFormat: String? = nil, codeArmRequired: Bool? = nil) {
        self.state = state; self.lastChanged = lastChanged; self.entityID = entityID
        self.supportedFeatures = supportedFeatures; self.codeFormat = codeFormat
        self.codeArmRequired = codeArmRequired
    }

    /// From `GET /api/states/<entity>`; nil if the reply isn't an entity state.
    public static func fromJson(_ body: String) -> AlarmState? {
        guard let data = body.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let state = (obj["state"] as? String), !state.isEmpty else { return nil }
        let changed = (obj["last_changed"] as? String).flatMap(parseOffsetDateTime)
        let attributes = obj["attributes"] as? [String: Any] ?? [:]
        let number = attributes["supported_features"] as? NSNumber
        let features = number.flatMap { value -> Int? in
            let d = value.doubleValue
            guard CFGetTypeID(value) != CFBooleanGetTypeID(), d.isFinite, d >= 0,
                  d < Double(Int.max), d.rounded(.towardZero) == d else { return nil }
            return Int(d)
        }
        return AlarmState(state: state, lastChanged: changed, entityID: obj["entity_id"] as? String,
            supportedFeatures: features, codeFormat: attributes["code_format"] as? String,
            codeArmRequired: attributes["code_arm_required"] as? Bool)
    }
}

/// Home/Away have feature bits; Disarm has none. A code format is not a capability flag:
/// Home Assistant may supply a configured default code that is absent from the state reply.
public func alarmAvailableActions(_ state: AlarmState?) -> [AlarmAction] {
    guard let state else { return [] }
    return actionsFor(state.state).filter { action in
        switch action {
        case .armHome: return state.supportedFeatures.map { $0 & 1 != 0 } ?? false
        case .armAway: return state.supportedFeatures.map { $0 & 2 != 0 } ?? false
        case .disarm: return true
        }
    }
}

/// What each button does in Home Assistant, and which state means it's "on".
public enum AlarmAction: String, Sendable, CaseIterable {
    case armHome, armAway, disarm
    public var service: String { switch self { case .armHome: "alarm_arm_home"; case .armAway: "alarm_arm_away"; case .disarm: "alarm_disarm" } }
    public var label: String { switch self { case .armHome: "Arm home"; case .armAway: "Arm away"; case .disarm: "Disarm" } }
    public var target: String { switch self { case .armHome: "armed_home"; case .armAway: "armed_away"; case .disarm: "disarmed" } }
    /// Android gates Disarm behind biometric/dialog confirmation; arming fires directly.
    public var needsConfirm: Bool { self == .disarm }
}

/// How the status row reads and looks for a state.
public enum Tone: String, Sendable { case calm, home, away, busy, alert, unknown }

public struct StatusView: Sendable, Equatable { public let title: String; public let tone: Tone
    public init(_ title: String, _ tone: Tone) { self.title = title; self.tone = tone } }

/// Everything the card's status row says.
public struct CardView: Sendable, Equatable { public let title: String; public let tone: Tone; public let detail: String?
    public init(_ title: String, _ tone: Tone, _ detail: String?) { self.title = title; self.tone = tone; self.detail = detail } }

/// The shield glyph per state (maps from `Tone` in the Android `statusIcon`).
public enum AlarmGlyph: String, Sendable { case off, home, lock, alert }

// ── The front door (a `lock.*` entity) ───────────────────────────────────────
public enum LockAction: String, Sendable { case lock, unlock
    public var service: String { self == .lock ? "lock" : "unlock" }
    public var label: String { self == .lock ? "Lock" : "Unlock" }
    public var target: String { self == .lock ? "locked" : "unlocked" }
    /// Android gates Unlock behind biometric/dialog confirmation; locking fires directly.
    public var needsConfirm: Bool { self == .unlock } }

public struct LockView: Sendable, Equatable { public let title: String; public let secure: Bool?
    public init(_ title: String, _ secure: Bool?) { self.title = title; self.secure = secure } }
