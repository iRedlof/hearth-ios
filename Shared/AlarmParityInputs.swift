import Foundation
import HearthKit

/// Inert native capture inputs pass through the same identity/freshness/capability mapper as HA.
enum AlarmParityInputs {
    static let states = [
        "disarmed", "armed_home", "armed_away", "armed_night", "armed_vacation", "armed_custom_bypass",
        "arming", "disarming", "pending", "triggered", "offline", "setup", "first_failure",
        "panel_failed", "door_failed", "door_first_failure", "no_door", "long_names",
        "door_unlocked", "door_open", "door_jammed", "door_locking", "door_unlocking", "door_opening",
        "door_unknown", "door_unavailable", "panel_unavailable", "panel_unknown",
        "home_only", "away_only", "no_arm_modes", "code_required", "pending_arm", "failed_arm",
        "pending_door", "failed_door", "interrupted", "auth_failed", "door_bad_entity", "old_cache"
    ]
    private static let now = ISO8601DateFormatter().date(from: "2026-10-21T16:46:00Z")!
    private static let checked = now.addingTimeInterval(-300)
    private static let zone = TimeZone(identifier: "America/Los_Angeles")!
    private static let panelID = "alarm_control_panel.home"
    private static let doorID = "lock.front"

    static func snapshot(_ state: String) -> AlarmSnapshot {
        if state == "setup" {
            return AlarmFetchResult(setup: true).snapshot(now: now, zone: zone, locale: Locale(identifier: "en_US"))
        }
        let alarmStates = ["disarmed", "armed_home", "armed_away", "armed_night", "armed_vacation",
                           "armed_custom_bypass", "arming", "disarming", "pending", "triggered"]
        let panelState = alarmStates.contains(state) ? state
            : state == "panel_unavailable" ? "unavailable" : state == "panel_unknown" ? "unknown"
            : ["offline", "panel_failed", "pending_door", "failed_door"].contains(state) ? "armed_home" : "disarmed"
        let doorStates = ["unlocked", "open", "jammed", "locking", "unlocking", "opening", "unknown", "unavailable"]
        let doorState = state.hasPrefix("door_") && doorStates.contains(String(state.dropFirst(5)))
            ? String(state.dropFirst(5)) : "locked"
        let features = state == "home_only" ? 1 : state == "away_only" ? 2 : state == "no_arm_modes" ? 0 : 3
        var panelAttributes: [String: Any] = [
            "friendly_name": state == "long_names" ? "Upstairs family home alarm" : "Home Alarm",
            "supported_features": features
        ]
        if state == "code_required" {
            panelAttributes["code_format"] = "number"
            panelAttributes["code_arm_required"] = true
        }
        var readings: [String: HaStateReading] = [:]
        if state != "first_failure" {
            readings[panelID] = reading(panelID, panelState, panelAttributes, old: state == "old_cache")
        }
        if !["no_door", "door_first_failure", "first_failure"].contains(state) {
            readings[doorID] = reading(doorID, doorState, ["friendly_name": "Front Door", "supported_features": 0],
                old: state == "old_cache")
        }
        var errors: [String: String] = [:]
        if ["offline", "first_failure", "panel_failed"].contains(state) { errors[panelID] = "Can't reach Home Assistant" }
        if ["offline", "first_failure", "door_failed", "door_first_failure"].contains(state) {
            errors[doorID] = "Can't reach Home Assistant"
        }
        if state == "auth_failed" { errors[panelID] = "Signed out: sign in again"; errors[doorID] = errors[panelID] }
        if state == "door_bad_entity" { errors[doorID] = "Not found: check the entity" }
        var result = AlarmFetchResult(entityID: panelID, lockID: state == "no_door" ? "" : doorID,
            lockName: state == "long_names" ? "Main entrance beside the garage" : "Front Door",
            readings: readings, errors: errors).snapshot(now: now, zone: zone, locale: Locale(identifier: "en_US"))
        if ["pending_arm", "failed_arm", "pending_door", "failed_door", "interrupted"].contains(state) {
            let isDoor = state.hasSuffix("_door")
            result = alarmApplyingOperation(result, AlarmOperation(entityID: isDoor ? doorID : panelID,
                action: isDoor ? "unlock" : "armHome", startedAt: now,
                error: state.hasPrefix("failed_") ? "Service rejected: check Home Assistant"
                    : state == "interrupted" ? "Update interrupted · Refresh to check" : nil))
        }
        // An empty scope/revision renders the production controls as inert native labels.
        return result
    }

    private static func reading(_ id: String, _ state: String, _ attributes: [String: Any], old: Bool) -> HaStateReading {
        let body: [String: Any] = ["entity_id": id, "state": state,
                                 "last_changed": "2026-10-21T15:36:00Z", "attributes": attributes]
        return HaStateReading(entityID: id,
            json: String(data: try! JSONSerialization.data(withJSONObject: body), encoding: .utf8)!,
            checkedAt: old ? now.addingTimeInterval(-901) : checked)
    }
}
