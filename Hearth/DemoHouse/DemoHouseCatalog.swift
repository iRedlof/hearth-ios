#if DEBUG
import Foundation
import HearthKit

/// The one fictional house the demo-house render harness presents (docs/RENDER-HARNESS.md). All
/// entity IDs, friendly names and values are invented (reserved `example.com` host); nothing here
/// is a real home. It has what every screen needs: an alarm panel and a front-door lock, a garage
/// door (plus a gate and a blind, so the Garage door picker has something to offer and something
/// to leave out), doors and a window for Activity and Goodnight, a thermostat with room sensors,
/// lights, scripts, favourites, battery sensors and a car called Stargate. Compiled only in DEBUG
/// and inert unless `-demoHouse` is passed (see DemoHouse.swift).
enum DemoHouseCatalog {
    /// Clearly fictional, reserved-domain base URL. Never the sign-in screen's prefilled default.
    static let baseURL = "https://home.example.com"
    static let host = "home.example.com"

    static let alarmID = "alarm_control_panel.home_alarm"
    static let lockID = "lock.front_door"
    static let climateID = "climate.hallway"
    static let resumeID = "button.hallway_resume"
    static let carPrefix = "stargate"

    static let garageID = "cover.garage_door"

    static let sensorIDs = ["sensor.hallway_temperature", "sensor.bedroom_temperature", "sensor.outside_temperature"]
    static let doorIDs = [garageID, "binary_sensor.back_door", "binary_sensor.patio_door"]
    static let scriptIDs = ["script.movie_time", "script.good_night", "script.all_lights_off", "script.clean_floor"]
    static let lightPins = ["light.kitchen", "light.living_room"]
    static let favouriteIDs = ["switch.coffee_maker", "fan.bedroom", "light.corner_lamp", "input_boolean.guest_mode"]

    /// A complete, signed-in config: https + auth (so `carReady`/`hasAuth`), an `alarm_control_panel.`
    /// entity (so `isComplete`), a `climate.` entity (so `hasClimate`), the Alarm card's garage and
    /// populated entity lists, so `configuredWidgets` lists every `HomeWidgetKind` on Home.
    static var config: HaConfig {
        HaConfig(
            baseUrl: baseURL,
            token: "demo-house-long-lived-token",
            entityId: alarmID,
            refreshToken: "demo-house-refresh-token",
            lockId: lockID,
            lockName: "Front Door",
            climateId: climateID,
            resumeId: resumeID,
            sensorsJson: json(sensorIDs),
            doorIdsJson: json(doorIDs),
            scriptIdsJson: json(scriptIDs),
            lightPinsJson: json(lightPins),
            favouriteIdsJson: json(favouriteIDs),
            doorsChosen: true,
            garageId: garageID
        )
    }

    // MARK: - Single-entity state objects (`GET /api/states/{id}`)

    /// Every entity the app reads via `stateJson`, keyed by entity id. The `entity_id` field equals the
    /// key, which the readers validate before accepting the reading.
    static func stateObject(for id: String) -> [String: Any]? { allStateObjects.first { $0["entity_id"] as? String == id } }

    /// The full `GET /api/states` array (drives the Home Assistant page entity pickers too).
    static var allStateObjects: [[String: Any]] {
        var out: [[String: Any]] = []
        out.append(state(alarmID, "disarmed", ["friendly_name": "Home alarm", "supported_features": 7,
                                               "code_arm_required": false]))
        out.append(state(lockID, "locked", ["friendly_name": "Front Door"]))
        out.append(state(resumeID, "unknown", ["friendly_name": "Hallway resume"]))
        out.append(state(climateID, "heat", climateAttributes))
        out.append(state("sensor.hallway_temperature", "70",
                         ["friendly_name": "Hallway", "unit_of_measurement": "°F", "device_class": "temperature"]))
        out.append(state("sensor.bedroom_temperature", "68",
                         ["friendly_name": "Bedroom", "unit_of_measurement": "°F", "device_class": "temperature"]))
        out.append(state("sensor.outside_temperature", "55",
                         ["friendly_name": "Outside", "unit_of_measurement": "°F", "device_class": "temperature"]))
        // Covers: the garage (open, close and stop) and a gate can be the Alarm card's garage; the
        // blind cannot, so the Garage door picker must leave it out.
        out.append(state(garageID, "closed",
                         ["friendly_name": "Garage", "device_class": "garage", "supported_features": 11]))
        out.append(state("cover.side_gate", "closed",
                         ["friendly_name": "Side gate", "device_class": "gate", "supported_features": 3]))
        out.append(state("cover.living_room_blinds", "open",
                         ["friendly_name": "Living Room blinds", "device_class": "blind", "supported_features": 15]))
        // Doors and a window, for Activity and the Goodnight check.
        out.append(state("binary_sensor.back_door", "off",
                         ["friendly_name": "Back Door", "device_class": "door"]))
        out.append(state("binary_sensor.patio_door", "off",
                         ["friendly_name": "Patio Door", "device_class": "door"]))
        out.append(state("binary_sensor.kitchen_window", "off",
                         ["friendly_name": "Kitchen Window", "device_class": "window"]))
        // Lights (also served via LIGHTS_TEMPLATE; present in /api/states for the pickers).
        out.append(state("light.kitchen", "on", ["friendly_name": "Kitchen", "brightness": 204]))
        out.append(state("light.living_room", "on", ["friendly_name": "Living Room", "brightness": 150]))
        out.append(state("light.bedroom", "off", ["friendly_name": "Bedroom"]))
        out.append(state("light.porch", "on", ["friendly_name": "Porch", "brightness": 255]))
        out.append(state("light.corner_lamp", "off", ["friendly_name": "Corner lamp"]))
        // Favourites.
        out.append(state("switch.coffee_maker", "off", ["friendly_name": "Coffee maker"]))
        out.append(state("fan.bedroom", "off", ["friendly_name": "Bedroom fan"]))
        out.append(state("input_boolean.guest_mode", "off", ["friendly_name": "Guest mode"]))
        // Quick actions (scripts idle at "off").
        out.append(state("script.movie_time", "off", ["friendly_name": "Movie time"]))
        out.append(state("script.good_night", "off", ["friendly_name": "Good night"]))
        out.append(state("script.all_lights_off", "off", ["friendly_name": "All lights off"]))
        out.append(state("script.clean_floor", "off", ["friendly_name": "Clean floor"]))
        // Batteries (also served via BATTERY_TEMPLATE; present here for the pickers).
        for (id, name, level) in batteryRows {
            out.append(state(id, "\(level)",
                            ["friendly_name": name, "device_class": "battery", "unit_of_measurement": "%"]))
        }
        return out
    }

    private static var climateAttributes: [String: Any] {
        ["friendly_name": "Hallway thermostat", "temperature_unit": "°F",
         "current_temperature": 70, "current_humidity": 44, "temperature": 72,
         "target_temp_low": NSNull(), "target_temp_high": NSNull(),
         "hvac_action": "heating", "fan_mode": "auto", "fan_modes": ["auto", "on"],
         "hvac_modes": ["off", "heat", "cool", "heat_cool"],
         "min_temp": 45, "max_temp": 95, "target_temp_step": 1]
    }

    // MARK: - Template results (`POST /api/template`)

    /// CAR_TEMPLATE renders a JSON object of raw states for the discovered car. A healthy parked
    /// "Stargate", locked and home, 72% / 210 mi.
    static var carTemplateResult: String {
        let s: [String: Any] = [
            "sensor.battery_level": "72", "sensor.battery_range": "210",
            "sensor.charging": "Disconnected", "sensor.charger_power": "0",
            "sensor.time_to_full_charge": "0", "sensor.inside_temperature": "68",
            "binary_sensor.status": "off", "binary_sensor.charge_cable": "off",
            "binary_sensor.front_driver_door": "off", "binary_sensor.front_passenger_door": "off",
            "binary_sensor.rear_driver_door": "off", "binary_sensor.rear_passenger_door": "off",
            "binary_sensor.tire_pressure_warning_front_left": "off",
            "binary_sensor.tire_pressure_warning_front_right": "off",
            "binary_sensor.tire_pressure_warning_rear_left": "off",
            "binary_sensor.tire_pressure_warning_rear_right": "off",
            "cover.frunk": "closed", "cover.trunk": "closed", "cover.windows": "closed",
            "cover.charge_port_door": "closed", "lock.lock": "locked", "switch.sentry_mode": "off",
            "device_tracker.location": "home", "number.charge_limit": "80",
            "sensor.tire_pressure_front_left": "42", "sensor.tire_pressure_front_right": "42",
            "sensor.tire_pressure_rear_left": "42", "sensor.tire_pressure_rear_right": "42",
            "sensor.outside_temperature": "55", "sensor.odometer": "12345",
            "sensor.charge_energy_added": "12.5", "climate.climate": "off"]
        return serialize(["found": true, "prefix": carPrefix, "name": "Stargate", "unit": "mi",
                          "tempUnit": "°F", "pressureUnit": "psi", "statusSince": iso(minutesAgo: 90), "s": s])
    }

    /// LIGHTS_TEMPLATE renders an array of `light.*` rows.
    static var lightsTemplateResult: String {
        serialize([
            lightRow("light.kitchen", "Kitchen", on: true, brightness: 204),
            lightRow("light.living_room", "Living Room", on: true, brightness: 150),
            lightRow("light.bedroom", "Bedroom", on: false, brightness: nil),
            lightRow("light.porch", "Porch", on: true, brightness: 255, rgb: [255, 190, 120]),
            lightRow("light.corner_lamp", "Corner lamp", on: false, brightness: nil)
        ])
    }

    /// BATTERY_TEMPLATE renders an array of replaceable battery sensors: four healthy, one low.
    static var batteryTemplateResult: String {
        serialize(batteryRows.map { id, name, level in
            ["id": id, "name": name, "kind": "numeric", "state": "\(level)", "level": "\(level)"]
        })
    }

    static let batteryRows: [(String, String, Int)] = [
        ("sensor.front_door_lock_battery", "Front Door Lock Battery", 68),
        ("sensor.backyard_motion_battery", "Backyard Motion Battery", 92),
        ("sensor.living_room_remote_battery", "Living Room Remote Battery", 54),
        ("sensor.garage_sensor_battery", "Garage Sensor Battery", 80),
        ("sensor.patio_door_battery", "Patio Door Battery", 22)
    ]

    // MARK: - Logbook (`GET /api/logbook/...`) for the Activity widget

    static var logbookResult: String {
        serialize([
            logbookEntry(garageID, "closed", "Garage", minutesAgo: 8),
            logbookEntry(alarmID, "disarmed", "Home alarm", minutesAgo: 35),
            logbookEntry(lockID, "unlocked", "Front Door", minutesAgo: 52),
            logbookEntry("binary_sensor.back_door", "off", "Back Door", minutesAgo: 95),
            logbookEntry("binary_sensor.patio_door", "on", "Patio Door", minutesAgo: 110),
            logbookEntry("lock.\(carPrefix)_lock", "locked", "Stargate", minutesAgo: 140)
        ])
    }

    // MARK: - Builders

    private static func state(_ id: String, _ value: String, _ attributes: [String: Any]) -> [String: Any] {
        ["entity_id": id, "state": value, "last_changed": iso(minutesAgo: 5),
         "last_updated": iso(minutesAgo: 5), "attributes": attributes]
    }

    private static func lightRow(_ id: String, _ name: String, on: Bool, brightness: Int?,
                                 rgb: [Int]? = nil) -> [String: Any] {
        ["entity_id": id, "state": on ? "on" : "off", "name": name, "since": iso(minutesAgo: 20),
         "group": false, "brightness": brightness.map { $0 as Any } ?? NSNull(),
         "rgb": rgb.map { $0 as Any } ?? NSNull()]
    }

    private static func logbookEntry(_ id: String, _ state: String, _ name: String, minutesAgo: Int) -> [String: Any] {
        ["entity_id": id, "state": state, "name": name, "when": iso(minutesAgo: minutesAgo)]
    }

    static func json(_ array: [String]) -> String { serialize(array) }

    private static func serialize(_ object: Any) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: object),
              let string = String(data: data, encoding: .utf8) else { return "{}" }
        return string
    }

    private static func iso(minutesAgo: Int) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: Date().addingTimeInterval(TimeInterval(-minutesAgo * 60)))
    }
}
#endif
