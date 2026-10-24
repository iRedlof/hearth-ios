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
        return thermostatSnapshot(state, name: name, now: now, stale: false, checkedAt: now,
                                  sensors: [], canResume: !config.resumeId.isEmpty)
    } catch {
        return thermostatSnapshot(nil, name: "Thermostat", now: now, stale: true, checkedAt: now)
    }
}
