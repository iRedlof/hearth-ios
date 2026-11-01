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
    @Parameter(title: "Selection revision") var selectionRevision: String
    @Parameter(title: "Observed mode") var expectedMode: String
    init() { action = ""; entityID = ""; scope = ""; resumeID = ""; revision = ""; selectionRevision = ""; expectedMode = "" }
    init(_ action: String, entityID: String, scope: String, revision: String, resumeID: String = "",
         selectionRevision: String = "", expectedMode: String = "") {
        self.action = action; self.entityID = entityID; self.scope = scope; self.resumeID = resumeID
        self.revision = revision
        self.selectionRevision = selectionRevision; self.expectedMode = expectedMode
    }
    func perform() async throws -> some IntentResult {
        try await ClimateActionRuntime.perform(scope: scope, entityID: entityID, revision: revision,
            resumeID: resumeID, action: action, selectionRevision: selectionRevision,
            expectedMode: expectedMode.isEmpty ? nil : expectedMode)
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
    @Parameter(title: "Selection revision") var selectionRevision: String
    @Parameter(title: "Observed mode") var expectedMode: String
    init() { kind = ""; entityID = ""; scope = ""; revision = ""; selectionRevision = ""; expectedMode = "" }
    init(_ kind: String, entityID: String, scope: String, revision: String,
         selectionRevision: String = "", expectedMode: String = "") {
        self.kind = kind; self.entityID = entityID; self.scope = scope; self.revision = revision
        self.selectionRevision = selectionRevision; self.expectedMode = expectedMode
    }
    @MainActor func perform() async throws -> some IntentResult {
        guard !revision.isEmpty, ["mode", "fan"].contains(kind), let context = HaConfigStore.context(),
              let config = context.config, let selection = ThermostatSelectionOrigin(context),
              selectionRevision.isEmpty || selectionRevision == selection.selectionRevision else { return .result() }
        let presentation = ClimateGate.shared.reservePresentation()
        let authorized: @Sendable () -> Bool = {
            presentation.lifetime.isActive() && ClimateActionRuntime.current(scope: scope, entityID: entityID, revision: revision,
                config: config, selectionRevision: selection.selectionRevision)
        }
        guard authorized(), let state = try await ClimateActionRuntime.read(config, isAuthorized: authorized),
              authorized(), ClimateGate.shared.presentationCurrent(presentation.id) else { return .result() }
        let options = climateOptions(state, kind: kind)
        let current = kind == "fan" ? state.fanMode : state.mode
        guard options.contains(where: { $0 != current }) else { return .result() }
        ClimateGate.shared.present(kind: kind, options: options, current: current,
            scope: scope, entityID: entityID, revision: revision,
            selectionRevision: selection.selectionRevision,
            expectedMode: expectedMode.isEmpty ? state.mode : expectedMode, presentationID: presentation.id)
        return .result()
    }
}
