import Foundation

public struct ThermostatFetchResult: Sendable {
    public let entityID: String
    public let sensorIDs: [String]
    public let readings: [String: HaStateReading]
    public let errors: [String: String]
    public let setup: Bool
    public let resumeID: String

    public init(entityID: String = "", sensorIDs: [String] = [], readings: [String: HaStateReading] = [:],
                errors: [String: String] = [:], setup: Bool = false, resumeID: String = "") {
        self.entityID = entityID; self.sensorIDs = sensorIDs; self.readings = readings
        self.errors = errors; self.setup = setup; self.resumeID = resumeID
    }

    public func snapshot(now: Date = .now, zone: TimeZone = .current,
                         locale: Locale = .current) -> ThermostatSnapshot {
        let reading = readings[entityID]
        let state = reading.flatMap { ClimateState.fromJson($0.json) }
        let error = errors[entityID]
        let historical = error != nil
        let sensors = sensorIDs.map { id in
            thermostatSensor(id: id, reading: readings[id], stale: errors[id] != nil)
        }
        var value = thermostatSnapshot(state,
            name: reading.flatMap { friendlyName(ofStateJson: $0.json) } ?? "Thermostat", now: now,
            stale: historical, checkedAt: reading?.checkedAt, sensors: sensors,
            canResume: resumeID.hasPrefix("button."), zone: zone, locale: locale)
        value.entityID = entityID; value.resumeID = resumeID
        value.setup = setup
        if setup {
            value.status = "Tap to connect"
            value.roomSub = "No reading"
            value.needsSettings = true
        } else if let error {
            value.error = error
            value.needsSettings = beaconNeedsSettings(error)
            value.needsSignIn = beaconNeedsSignIn(error)
            value.status = error.contains("Can't reach") ? "Can't connect"
                : value.needsSignIn ? "Sign in again"
                : value.needsSettings ? "Check setup" : "Check failed"
        }
        return value
    }
}

/// The selected thermostat and sensors use real readings in the app and widget.
public func fetchThermostatReadings(_ config: HaConfig?, previous: [String: HaStateReading] = [:],
                                   now: Date = .now,
                                   request: (@Sendable (String) async throws -> String)? = nil) async -> ThermostatFetchResult {
    guard let config, config.hasClimate else { return ThermostatFetchResult(setup: true) }
    var seen = Set<String>()
    let sensors = Array(config.sensorIds.filter { !$0.isEmpty && seen.insert($0).inserted }.prefix(3))
    let result = await fetchHaStateReadings(config, ids: [config.climateId] + sensors,
        previous: previous, now: now, request: request)
    return ThermostatFetchResult(entityID: config.climateId, sensorIDs: sensors,
        readings: result.readings, errors: result.errors, resumeID: config.resumeId)
}

public func fetchThermostatSnapshot(_ config: HaConfig, now: Date = .now) async -> ThermostatSnapshot {
    await fetchThermostatReadings(config, now: now).snapshot(now: now)
}

private func thermostatSensor(id: String, reading: HaStateReading?, stale: Bool) -> ThermostatSensor {
    let fallback = id.split(separator: ".").last.map(String.init)?.replacingOccurrences(of: "_", with: " ").capitalizedFirst ?? "Sensor"
    guard let reading, let data = reading.json.data(using: .utf8),
          let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        return ThermostatSensor(name: fallback, value: "—", id: id, stale: stale)
    }
    let attrs = obj["attributes"] as? [String: Any]
    let name = attrs?["friendly_name"] as? String ?? fallback
    let unit = attrs?["unit_of_measurement"] as? String ?? ""
    let state = obj["state"] as? String ?? ""
    let value: String
    if let d = Double(state) {
        if climateNumber(d) != nil {
            let number = d.truncatingRemainder(dividingBy: 1) == 0
                ? String(Int(d)) : String(format: "%.1f", d)
            value = unit.contains("°") || unit == "F" || unit == "C" ? degrees(d)
                : unit.isEmpty ? number : "\(number) \(unit)"
        } else { value = "—" }
    } else {
        value = ["", "unknown", "unavailable", "null"].contains(state.lowercased()) ? "—" : state.capitalizedFirst
    }
    return ThermostatSensor(name: name, value: value, id: id, stale: stale)
}
