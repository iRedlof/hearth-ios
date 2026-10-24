import Foundation

/// Fetches the live Thermostat snapshot — the `climate.*` state mapped to the `ThermostatSnapshot`
/// the widget renders. Mirrors Android `ClimateRepository`. Returns `.sample` when no thermostat is
/// configured. (Room sensors arrive with the sensor picker in a later slice.)
public func fetchThermostatSnapshot(_ config: HaConfig, now: Date = Date()) async -> ThermostatSnapshot {
    guard config.hasClimate else { return .sample }
    let client = HaClient(config)
    do {
        let json = try await client.stateJson(config.climateId)
        let state = ClimateState.fromJson(json)
        let name = friendlyName(ofStateJson: json) ?? "Thermostat"
        let sensors = await readSensors(client, config.sensorIds)
        return thermostatSnapshot(state, name: name, now: now, stale: false, checkedAt: now,
                                  sensors: sensors, canResume: !config.resumeId.isEmpty)
    } catch {
        return thermostatSnapshot(nil, name: "Thermostat", now: now, stale: true, checkedAt: now)
    }
}

/// Reads up to three configured room sensors into display rows (name + formatted value).
private func readSensors(_ client: HaClient, _ ids: [String]) async -> [ThermostatSensor] {
    var out: [ThermostatSensor] = []
    for id in ids.prefix(3) {
        guard let json = try? await client.stateJson(id), let reading = sensorReading(json) else { continue }
        out.append(reading)
    }
    return out
}

private func sensorReading(_ json: String) -> ThermostatSensor? {
    guard let data = json.data(using: .utf8),
          let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let state = obj["state"] as? String else { return nil }
    let attrs = obj["attributes"] as? [String: Any]
    let name = (attrs?["friendly_name"] as? String) ?? "Sensor"
    let unit = (attrs?["unit_of_measurement"] as? String) ?? ""
    let value: String
    if let d = Double(state) {
        let n = Int(d.rounded())
        value = (unit.contains("°") || unit == "F" || unit == "C") ? "\(n)°" : (unit.isEmpty ? "\(n)" : "\(n) \(unit)")
    } else {
        value = state.capitalized
    }
    return ThermostatSensor(name: name, value: value)
}
