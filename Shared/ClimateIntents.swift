import AppIntents
import WidgetKit
import HearthKit

/// Setpoint ± and Resume, in place (Android gates these only by lock-screen unlock, which doesn't
/// apply to a home-screen widget). Reads the live climate state, nudges one step, and calls
/// `climate.set_temperature`; Resume presses the configured `button.*`.
struct ClimateSetpointIntent: AppIntent {
    static var title: LocalizedStringResource { "Adjust thermostat" }
    static var isDiscoverable: Bool { false }

    @Parameter(title: "Action") var action: String   // heatUp | heatDown | coolUp | coolDown | resume
    init() {}
    init(_ action: String) { self.action = action }

    func perform() async throws -> some IntentResult {
        guard let config = HaConfigStore.load(), config.hasClimate else { return .result() }
        let client = HaClient(config)
        if action == "resume" {
            if !config.resumeId.isEmpty {
                try await client.callService(domain: "button", service: "press", entityId: config.resumeId)
            }
        } else {
            let json = try await client.stateJson(config.climateId)
            guard let state = ClimateState.fromJson(json) else { return .result() }
            let side: ClimateSide = action.hasPrefix("cool") ? .cool : .heat
            let step = action.hasSuffix("Up") ? 1 : -1
            if let data = setpointNudge(state, side: side, by: step) {
                try await client.callService(domain: "climate", service: "set_temperature",
                                             entityId: config.climateId, data: data.mapValues { $0 as Any })
            }
        }
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}

/// Mode / Fan — a choice, so (like Android's picker) `openAppWhenRun` brings Hearth forward and
/// `ClimateGate` shows the options; picking one calls `set_hvac_mode` / `set_fan_mode`.
struct ClimatePickerIntent: AppIntent {
    static var title: LocalizedStringResource { "Choose thermostat option" }
    static var isDiscoverable: Bool { false }
    static var openAppWhenRun: Bool { true }

    @Parameter(title: "Kind") var kind: String   // mode | fan
    init() {}
    init(_ kind: String) { self.kind = kind }

    @MainActor
    func perform() async throws -> some IntentResult {
        guard let config = HaConfigStore.load(), config.hasClimate,
              let json = try? await HaClient(config).stateJson(config.climateId),
              let state = ClimateState.fromJson(json) else { return .result() }
        let options = kind == "fan" ? state.fanModes : state.modes
        let current = kind == "fan" ? state.fanMode : state.mode
        ClimateGate.shared.present(kind: kind, options: options, current: current)
        return .result()
    }
}
