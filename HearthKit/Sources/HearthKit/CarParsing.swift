import Foundation

/// The exact Home Assistant Jinja template the car widget renders (`POST /api/template`).
/// Auto-discovers the Tesla integration's entity prefix and returns a compact JSON of raw states.
/// Ported verbatim from Android `CarState.kt:CAR_TEMPLATE`.
public let CAR_TEMPLATE = """
{%- set ns = namespace(p='', any='') -%}
{%- set locks = states.lock | map(attribute='entity_id') | list -%}
{%- for s in states.sensor if s.entity_id.endswith('_battery_range') -%}
  {%- set p = s.entity_id[7:-14] -%}
  {%- if ('lock.' ~ p ~ '_lock') in locks -%}
    {#- a car: its range and its lock; the one reporting now first, else one whose readings are all unknown (asleep, or its integration not reporting) -#}
    {%- if ns.p == '' and states('sensor.' ~ p ~ '_battery_level') | is_number -%}{%- set ns.p = p -%}{%- endif -%}
    {%- if ns.any == '' -%}{%- set ns.any = p -%}{%- endif -%}
  {%- endif -%}
{%- endfor -%}
{%- set p = ns.p or ns.any -%}
{%- if p == '' -%}{{ {'found': false} | to_json }}{%- else -%}
{%- set keys = ['sensor.battery_level', 'sensor.battery_range', 'sensor.charging', 'sensor.charger_power', 'sensor.time_to_full_charge', 'sensor.inside_temperature', 'binary_sensor.status', 'binary_sensor.charge_cable', 'binary_sensor.front_driver_door', 'binary_sensor.front_passenger_door', 'binary_sensor.rear_driver_door', 'binary_sensor.rear_passenger_door', 'binary_sensor.tire_pressure_warning_front_left', 'binary_sensor.tire_pressure_warning_front_right', 'binary_sensor.tire_pressure_warning_rear_left', 'binary_sensor.tire_pressure_warning_rear_right', 'cover.frunk', 'cover.trunk', 'cover.windows', 'cover.charge_port_door', 'lock.lock', 'switch.sentry_mode', 'device_tracker.location', 'number.charge_limit', 'sensor.tire_pressure_front_left', 'sensor.tire_pressure_front_right', 'sensor.tire_pressure_rear_left', 'sensor.tire_pressure_rear_right', 'sensor.outside_temperature', 'sensor.odometer', 'sensor.charge_energy_added', 'climate.climate'] -%}
{%- set out = namespace(s={}) -%}
{%- for k in keys -%}{%- set e = k.split('.')[0] ~ '.' ~ p ~ '_' ~ k.split('.')[1] -%}{%- set out.s = dict(out.s, **{k: states(e)}) -%}{%- endfor -%}
{%- set st = 'binary_sensor.' ~ p ~ '_status' -%}
{{ {'found': true, 'prefix': p, 'name': (state_attr('sensor.' ~ p ~ '_battery_level', 'friendly_name') or p) | replace(' Battery level', '') | replace(' battery level', ''), 'unit': state_attr('sensor.' ~ p ~ '_battery_range', 'unit_of_measurement') or 'mi', 'tempUnit': state_attr('sensor.' ~ p ~ '_inside_temperature', 'unit_of_measurement') or '', 'pressureUnit': state_attr('sensor.' ~ p ~ '_tire_pressure_front_left', 'unit_of_measurement') or '', 'statusSince': (states[st].last_changed.isoformat() if states[st] is defined and states[st] else none), 's': out.s} | to_json }}
{%- endif -%}
"""

let carUnknownStates: Set<String> = ["unknown", "unavailable", "none", ""]

/// ISO-8601 with offset, tolerating fractional seconds of any precision (HA emits microseconds).
func parseOffsetDateTime(_ raw: String?) -> Date? {
    guard var str = raw, !str.isEmpty else { return nil }
    // Normalise fractional seconds to <=3 digits (ISO8601DateFormatter expects milliseconds).
    if let dot = str.firstIndex(of: ".") {
        let after = str.index(after: dot)
        if let tz = str[after...].firstIndex(where: { "+-Z".contains($0) }) {
            let frac = str[after..<tz]
            if frac.count > 3 { str.replaceSubrange(after..<tz, with: String(frac.prefix(3))) }
        }
    }
    let iso = ISO8601DateFormatter()
    iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let d = iso.date(from: str) { return d }
    iso.formatOptions = [.withInternetDateTime]
    return iso.date(from: str)
}

private func roundedInt(_ d: Double) -> Int { Int(d.rounded()) }

/// The car from CAR_TEMPLATE's reply; nil if Home Assistant has no car.
/// Ported from Android `CarState.kt:carFromTemplate`.
public func carFromTemplate(_ json: String?) -> Car? {
    guard let json, let data = json.data(using: .utf8),
          let o = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return nil }
    guard (o["found"] as? Bool) == true else { return nil }
    let s = (o["s"] as? [String: Any]) ?? [:]

    func raw(_ k: String) -> String? {
        guard let v = s[k] as? String else { return nil }
        let t = v.trimmingCharacters(in: .whitespacesAndNewlines)
        return carUnknownStates.contains(t.lowercased()) ? nil : t
    }
    func num(_ k: String) -> Double? {
        guard let r = raw(k), let d = Double(r), d.isFinite else { return nil }
        return d
    }
    func on(_ k: String) -> Bool { raw(k) == "on" }
    func topString(_ k: String) -> String { (o[k] as? String) ?? "" }

    let plugged = on("binary_sensor.charge_cable")
    let pluggedKnown = ["on", "off"].contains(raw("binary_sensor.charge_cable") ?? "")

    var open: [String] = []
    if ["front_driver", "front_passenger", "rear_driver", "rear_passenger"].contains(where: { on("binary_sensor.\($0)_door") }) { open.append("Door") }
    if raw("cover.frunk") == "open" { open.append("Frunk") }
    if raw("cover.trunk") == "open" { open.append("Trunk") }
    if raw("cover.windows") == "open" { open.append("Windows") }
    if raw("cover.charge_port_door") == "open" && pluggedKnown && !plugged { open.append("Charge port") }

    let name0 = topString("name")
    let unit0 = topString("unit")
    let locked: Bool? = switch raw("lock.lock") { case "locked": true; case "unlocked", "open": false; default: nil }

    let place: String? = {
        guard let p = raw("device_tracker.location") else { return nil }
        if p == "home" { return "Home" }
        if p == "not_home" { return "Away" }
        return p.prefix(1).uppercased() + p.dropFirst()
    }()

    let tiresInt: [Int]? = {
        let v = ["front_left", "front_right", "rear_left", "rear_right"].map { num("sensor.tire_pressure_\($0)").map(roundedInt) }
        return v.allSatisfy { $0 != nil } ? v.compactMap { $0 } : nil
    }()
    let tiresPrecise: [Double]? = {
        let v = ["front_left", "front_right", "rear_left", "rear_right"].map { num("sensor.tire_pressure_\($0)") }
        return v.allSatisfy { $0 != nil && $0!.isFinite } ? v.compactMap { $0 } : nil
    }()

    let openKnown =
        ["front_driver", "front_passenger", "rear_driver", "rear_passenger"].allSatisfy { ["on", "off"].contains(raw("binary_sensor.\($0)_door") ?? "") } &&
        ["frunk", "trunk", "windows"].allSatisfy { ["open", "closed"].contains(raw("cover.\($0)") ?? "") } &&
        (plugged || ["open", "closed"].contains(raw("cover.charge_port_door") ?? ""))

    let statusSince = (o["statusSince"] as? String).flatMap { $0.isEmpty || $0 == "null" ? nil : $0 }

    return Car(
        name: name0.isEmpty ? "Car" : name0,
        battery: num("sensor.battery_level").map(roundedInt),
        range: num("sensor.battery_range").map(roundedInt),
        unit: unit0.isEmpty ? "mi" : unit0,
        chargeState: raw("sensor.charging")?.lowercased(),
        plugged: plugged,
        chargerKw: num("sensor.charger_power"),
        fullAt: parseOffsetDateTime(raw("sensor.time_to_full_charge")),
        limit: num("number.charge_limit").map(roundedInt),
        locked: locked,
        open: open,
        tireWarning: ["front_left", "front_right", "rear_left", "rear_right"].contains(where: { on("binary_sensor.tire_pressure_warning_\($0)") }),
        sentry: on("switch.sentry_mode"),
        place: place,
        inside: num("sensor.inside_temperature").map(roundedInt),
        tempUnit: topString("tempUnit"),
        awake: raw("binary_sensor.status").map { $0 == "on" },
        since: parseOffsetDateTime(statusSince),
        tires: tiresInt,
        pressureUnit: topString("pressureUnit"),
        outside: num("sensor.outside_temperature").map(roundedInt),
        odometer: num("sensor.odometer").map(roundedInt),
        addedKwh: num("sensor.charge_energy_added").map { ($0 * 10).rounded() / 10.0 },
        climateOn: raw("climate.climate").map { $0 != "off" },
        sentryKnown: ["on", "off"].contains(raw("switch.sentry_mode") ?? ""),
        pluggedKnown: pluggedKnown,
        openKnown: openKnown,
        preciseTires: tiresPrecise,
        preciseInside: num("sensor.inside_temperature"),
        preciseOutside: num("sensor.outside_temperature"))
}

/// What the widget shows: the car now, or (no readings now) the last real ones, stale.
public func carToShow(_ current: Car?, _ lastGood: Car?) -> CarShown? {
    guard let current else { return nil }
    if current.battery == nil, let lastGood, lastGood.battery != nil { return CarShown(car: lastGood, stale: true) }
    return CarShown(car: current, stale: false)
}
