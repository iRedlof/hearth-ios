import Foundation

/// The alarm as Home Assistant reports it (`alarm_control_panel.*`). Ported from Android `AlarmState.kt`.
public struct AlarmState: Sendable, Equatable {
    public let state: String
    public let lastChanged: Date?
    public init(state: String, lastChanged: Date?) { self.state = state; self.lastChanged = lastChanged }

    /// From `GET /api/states/<entity>`; nil if the reply isn't an entity state.
    public static func fromJson(_ body: String) -> AlarmState? {
        guard let data = body.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let state = (obj["state"] as? String), !state.isEmpty else { return nil }
        let changed = (obj["last_changed"] as? String).flatMap(parseOffsetDateTime)
        return AlarmState(state: state, lastChanged: changed)
    }
}

/// What each button does in Home Assistant, and which state means it's "on".
public enum AlarmAction: String, Sendable, CaseIterable {
    case armHome, armAway, disarm
    public var service: String { switch self { case .armHome: "alarm_arm_home"; case .armAway: "alarm_arm_away"; case .disarm: "alarm_disarm" } }
    public var label: String { switch self { case .armHome: "Arm home"; case .armAway: "Arm away"; case .disarm: "Disarm" } }
    public var target: String { switch self { case .armHome: "armed_home"; case .armAway: "armed_away"; case .disarm: "disarmed" } }
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
    public var target: String { self == .lock ? "locked" : "unlocked" } }

public struct LockView: Sendable, Equatable { public let title: String; public let secure: Bool?
    public init(_ title: String, _ secure: Bool?) { self.title = title; self.secure = secure } }
