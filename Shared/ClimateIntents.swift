import AppIntents
import HearthKit

/// Setpoint and Resume remain bound to the account and device displayed by the widget.
struct ClimateSetpointIntent: AppIntent {
    static var title: LocalizedStringResource { "Adjust thermostat" }
    static var isDiscoverable: Bool { false }
    @Parameter(title: "Action") var action: String
    @Parameter(title: "Thermostat") var entityID: String
    @Parameter(title: "Account scope") var scope: String
    @Parameter(title: "Resume button") var resumeID: String
    @Parameter(title: "Control revision") var revision: String
    init() { action = ""; entityID = ""; scope = ""; resumeID = ""; revision = "" }
    init(_ action: String, entityID: String, scope: String, revision: String, resumeID: String = "") {
        self.action = action; self.entityID = entityID; self.scope = scope; self.resumeID = resumeID
        self.revision = revision
    }
    func perform() async throws -> some IntentResult {
        try await ClimateActionRuntime.perform(scope: scope, entityID: entityID, revision: revision,
            resumeID: resumeID, action: action)
        return .result()
    }
}

/// Mode/Fan opens actual choices instead of changing mode on the initial tap.
struct ClimatePickerIntent: AppIntent {
    static var title: LocalizedStringResource { "Choose thermostat option" }
    static var isDiscoverable: Bool { false }
    static var openAppWhenRun: Bool { true }
    @Parameter(title: "Kind") var kind: String
    @Parameter(title: "Thermostat") var entityID: String
    @Parameter(title: "Account scope") var scope: String
    @Parameter(title: "Control revision") var revision: String
    init() { kind = ""; entityID = ""; scope = ""; revision = "" }
    init(_ kind: String, entityID: String, scope: String, revision: String) {
        self.kind = kind; self.entityID = entityID; self.scope = scope; self.revision = revision
    }
    @MainActor func perform() async throws -> some IntentResult {
        guard !revision.isEmpty, ["mode", "fan"].contains(kind), let config = HaConfigStore.load(),
              ClimateActionRuntime.current(scope: scope, entityID: entityID, revision: revision, config: config),
              let state = try await ClimateActionRuntime.read(config),
              ClimateActionRuntime.current(scope: scope, entityID: entityID, revision: revision, config: config) else { return .result() }
        let options = climateOptions(state, kind: kind)
        let current = kind == "fan" ? state.fanMode : state.mode
        guard options.contains(where: { $0 != current }) else { return .result() }
        ClimateGate.shared.present(kind: kind, options: options, current: current,
            scope: scope, entityID: entityID, revision: revision)
        return .result()
    }
}
