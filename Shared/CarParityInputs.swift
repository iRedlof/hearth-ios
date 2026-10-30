import Foundation
import HearthKit

/// Inert raw HA responses use the production cache-to-snapshot mapper, rather than handwritten
/// display snapshots. The first ten inputs match Android's beacon-states.json.
enum CarParityInputs {
    static let states = ["parked", "charging", "complete", "sentry", "low_battery", "open", "tires",
                         "unlocked_away", "offline", "no_reading", "limit_90", "no_limit",
                         "stale_sentry", "old_reading", "no_car", "setup", "first_failure",
                         "unknown_security", "battery_100", "auth_failed"]
    private static let now = Date(timeIntervalSince1970: 1_792_515_600) // 2026-10-20 17:00Z
    private static let checked = Date(timeIntervalSince1970: 1_792_514_460) // 16:41Z
    private static let zone = TimeZone(identifier: "America/Los_Angeles")!
    private static let locale = Locale(identifier: "en_US")

    static func snapshot(_ state: String) -> CarSnapshot {
        if state == "setup" {
            return CarFetchResult(cache: nil, setup: true).snapshot(now: now, zone: zone, locale: locale)
        }
        if state == "first_failure" {
            return CarFetchResult(cache: nil, error: "Can't reach Home Assistant")
                .snapshot(now: now, zone: zone, locale: locale)
        }
        if state == "auth_failed" {
            return CarFetchResult(cache: nil, error: "Signed out: sign in again")
                .snapshot(now: now, zone: zone, locale: locale)
        }
        let old = reply(state == "old_reading" ? "parked" : state)
        let cache = CarReadingsCache(current: reply(state), lastGood: old, checkedAt: checked)
        let error = ["offline", "stale_sentry"].contains(state) ? "Can't reach Home Assistant" : nil
        return CarFetchResult(cache: cache, error: error).snapshot(now: now, zone: zone, locale: locale)
    }

    private static func reply(_ state: String) -> String {
        if state == "no_car" { return #"{"found":false}"# }
        let noReading = state == "no_reading"
        var s: [String: String] = [
            "sensor.battery_level": state == "charging" ? "64" : state == "complete" ? "80"
                : state == "low_battery" ? "18" : state == "battery_100" ? "100" : "79",
            "sensor.battery_range": state == "charging" ? "196" : state == "complete" ? "245"
                : state == "low_battery" ? "55" : "242",
            "number.charge_limit": state == "limit_90" ? "90" : state == "no_limit" ? "unknown"
                : state == "battery_100" ? "100" : "80",
            "sensor.inside_temperature": "69", "sensor.outside_temperature": "55",
            "lock.lock": ["open", "unlocked_away"].contains(state) ? "unlocked" : "locked",
            "switch.sentry_mode": ["sentry", "stale_sentry"].contains(state) ? "on" : "off",
            "binary_sensor.status": ["charging", "open", "unlocked_away", "low_battery"].contains(state) ? "on" : "off",
            "binary_sensor.charge_cable": ["charging", "complete"].contains(state) ? "on" : "off",
            "sensor.charging": state == "charging" ? "charging" : state == "complete" ? "complete" : "disconnected",
            "device_tracker.location": state == "unlocked_away" ? "not_home" : "home",
        ]
        for door in ["front_driver", "front_passenger", "rear_driver", "rear_passenger"] {
            s["binary_sensor.\(door)_door"] = "off"
        }
        for cover in ["frunk", "trunk", "windows", "charge_port_door"] {
            s["cover.\(cover)"] = state == "open" && cover == "trunk" ? "open" : "closed"
        }
        let pressures = state == "tires" ? [38, 39, 31, 40] : [38, 39, 40, 40]
        for (i, wheel) in ["front_left", "front_right", "rear_left", "rear_right"].enumerated() {
            s["sensor.tire_pressure_\(wheel)"] = String(pressures[i])
            s["binary_sensor.tire_pressure_warning_\(wheel)"] = state == "tires" && i == 2 ? "on" : "off"
        }
        if state == "charging" {
            s["sensor.charger_power"] = "11.5"; s["sensor.time_to_full_charge"] = "2026-10-21T07:40:00Z"
        }
        if noReading { s = s.mapValues { _ in "unknown" } }
        if state == "old_reading" { s["sensor.battery_level"] = "unknown" }
        if state == "unknown_security" {
            s["switch.sentry_mode"] = "unknown"; s["lock.lock"] = "unknown"
            s["cover.trunk"] = "unavailable"; s["binary_sensor.charge_cable"] = "unavailable"
        }
        let raw: [String: Any] = ["found": true, "prefix": "stargate", "name": "Stargate",
            "s": s, "unit": "mi", "tempUnit": "°F", "pressureUnit": "psi",
            "statusSince": noReading ? NSNull() : "2026-10-20T05:33:00Z"]
        return String(data: try! JSONSerialization.data(withJSONObject: raw), encoding: .utf8)!
    }
}
