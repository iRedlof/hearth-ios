import Foundation
import HearthKit

/// Native gallery scenarios use production parsing and capability mapping from inert HA replies.
enum ThermostatParityInputs {
    static let states = [
        "auto", "heating", "cooling", "heat_idle", "cool_idle", "auto_heating", "auto_cooling",
        "fan", "off", "offline", "setup", "first_failure", "unknown_room", "unknown_targets",
        "no_controls", "no_fan_mode", "heat_min", "heat_max", "cool_min", "cool_max",
        "range_min", "range_max", "one_target", "celsius", "long_names", "sensor_failed",
        "auth_failed", "bad_entity", "pending_target", "failed_target", "pending_mode",
        "pending_fan", "pending_resume", "fan_only", "dry", "unavailable", "pending_no_fan_mode",
        "unavailable_no_fan_mode"
    ]
    private static let now = Date(timeIntervalSince1970: 1_792_515_600)
    private static let checked = Date(timeIntervalSince1970: 1_792_514_460)
    private static let zone = TimeZone(identifier: "America/Los_Angeles")!
    private static let entityID = "climate.thermostat"
    private static let sensors = ["sensor.outside", "sensor.bedroom", "sensor.thermo"]

    static func snapshot(_ state: String) -> ThermostatSnapshot {
        if state == "setup" { return ThermostatFetchResult(setup: true).snapshot(now: now) }
        var readings: [String: HaStateReading] = [:]
        if state != "first_failure" {
            readings[entityID] = reading(entityID, raw: reply(state))
            let values = state == "celsius" ? ["8", "19.5", "20.5"] : ["48", "67.5", "69.5"]
            for ((id, name), value) in zip(zip(sensors, ["Outside", "Bedroom", "Thermo"]), values) {
                readings[id] = reading(id, raw: [
                    "entity_id": id, "state": value,
                    "attributes": ["friendly_name": state == "long_names" ? name + " temperature sensor" : name,
                                   "unit_of_measurement": state == "celsius" ? "°C" : "°F"]
                ])
            }
        }
        var errors: [String: String] = [:]
        if ["offline", "first_failure"].contains(state) { errors[entityID] = "Can't reach Home Assistant" }
        if state == "auth_failed" { errors[entityID] = "Signed out: sign in again" }
        if state == "bad_entity" { errors[entityID] = "Not found: check the entity" }
        if state == "sensor_failed" { errors[sensors[1]] = "Can't reach Home Assistant" }
        let snapshot = ThermostatFetchResult(entityID: entityID, sensorIDs: sensors, readings: readings,
            errors: errors, resumeID: state == "no_controls" ? "" : "button.resume")
            .snapshot(now: now, zone: zone, locale: Locale(identifier: "en_US"))
        if state.hasPrefix("pending_") || state == "failed_target" {
            let action = state == "pending_mode" ? "mode" : state == "pending_fan" ? "fan"
                : state == "pending_resume" ? "resume" : "heatUp"
            return climateApplyingOperation(snapshot, ClimateOperation(entityID: entityID, action: action,
                startedAt: now, error: state == "failed_target" ? "Can't reach Home Assistant" : nil))
        }
        return snapshot
    }

    private static func reading(_ id: String, raw: [String: Any]) -> HaStateReading {
        HaStateReading(entityID: id,
            json: String(data: try! JSONSerialization.data(withJSONObject: raw), encoding: .utf8)!,
            checkedAt: checked)
    }
    private static func reply(_ state: String) -> [String: Any] {
        var mode = "heat_cool"
        if ["heating", "heat_idle", "heat_min", "heat_max", "no_fan_mode", "pending_no_fan_mode"].contains(state) { mode = "heat" }
        if ["cooling", "cool_idle", "cool_min", "cool_max"].contains(state) { mode = "cool" }
        if ["off", "fan_only", "dry", "unavailable"].contains(state) { mode = state }
        if state == "unavailable_no_fan_mode" { mode = "unavailable" }
        let heating = ["heating", "auto_heating"].contains(state)
        let cooling = ["cooling", "auto_cooling"].contains(state)
        var attributes: [String: Any] = [
            "friendly_name": state == "long_names" ? "Upstairs bedroom thermostat" : "Thermostat",
            "current_temperature": heating ? 65 : cooling ? 74 : 67,
            "current_humidity": 52, "temperature": heating ? 68 : cooling ? 70 : mode == "cool" ? 69 : 64,
            "target_temp_low": state == "auto_heating" || state == "auto_cooling" ? 68 : 64,
            "target_temp_high": state == "auto_heating" || state == "auto_cooling" ? 72 : 69,
            "min_temp": 45, "max_temp": 95, "target_temp_step": 1,
            "fan_mode": state == "fan" ? "on" : "auto", "fan_modes": ["auto", "on"],
            "hvac_modes": ["off", "heat", "cool", "heat_cool"],
            "hvac_action": heating ? "heating" : cooling ? "cooling" : state == "fan" || mode == "fan_only" ? "fan"
                : mode == "off" ? "off" : mode == "dry" ? "drying" : "idle"
        ]
        if state.hasSuffix("_min") {
            attributes["temperature"] = 45
            attributes["target_temp_low"] = 45
        }
        if state.hasSuffix("_max") {
            attributes["temperature"] = 95
            attributes["target_temp_high"] = 95
        }
        if state == "unknown_room" { attributes["current_temperature"] = NSNull() }
        if state == "unknown_targets" {
            attributes["target_temp_low"] = NSNull(); attributes["target_temp_high"] = NSNull()
        }
        if state == "one_target" { attributes["target_temp_high"] = NSNull() }
        if state == "no_controls" {
            attributes["hvac_modes"] = []; attributes["fan_modes"] = []
            attributes["target_temp_step"] = 0
        }
        if ["no_fan_mode", "pending_no_fan_mode", "unavailable_no_fan_mode"].contains(state) {
            attributes.removeValue(forKey: "fan_mode")
        }
        if state == "celsius" {
            attributes["current_temperature"] = -2.5
            attributes["target_temp_low"] = 19.5; attributes["target_temp_high"] = 24.5
            attributes["min_temp"] = 7; attributes["max_temp"] = 35; attributes["target_temp_step"] = 0.5
        }
        return ["entity_id": entityID, "state": mode, "attributes": attributes]
    }
}
