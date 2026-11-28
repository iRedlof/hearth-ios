import AppIntents
import HearthKit

/// Mode/Fan on the Home Screen widget: the chip row becomes the thermostat's live choices. The app stays closed.
struct ClimateInlinePickerIntent: AppIntent {
    static var title: LocalizedStringResource { "Show thermostat choices" }
    static var isDiscoverable: Bool { false }
    static var openAppWhenRun: Bool { false }
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
    /// The same guards as `ClimatePickerIntent`, ending in a saved record instead of an in-app dialog.
    @MainActor func perform() async throws -> some IntentResult {
        let kind = kind, entityID = entityID, scope = scope, revision = revision
        guard !revision.isEmpty, ["mode", "fan"].contains(kind), let context = HaConfigStore.context(),
              let config = context.config, let selection = ThermostatSelectionOrigin(context),
              selectionRevision.isEmpty || selectionRevision == selection.selectionRevision else { return .result() }
        let opening = ThermostatInlinePickerOpening.reserve()
        let authorized: @Sendable () -> Bool = {
            opening.isActive() && ClimateActionRuntime.current(scope: scope, entityID: entityID, revision: revision,
                config: config, selectionRevision: selection.selectionRevision)
        }
        guard authorized(), let state = try await ClimateActionRuntime.read(config, isAuthorized: authorized),
              authorized() else { return .result() }
        guard let record = thermostatInlinePicker(state: state, kind: kind, entityID: entityID, scope: scope,
            revision: revision, selectionRevision: selection.selectionRevision,
            expectedMode: expectedMode.isEmpty ? state.mode : expectedMode, now: .now) else { return .result() }
        try ThermostatInlinePickerStore.save(record)
        ThermostatInlinePickerStore.reloadWidget()
        return .result()
    }
}

/// One chip of the opened row. The record is spent before anything is sent, so a second tap cannot repeat it.
struct ClimateInlineChoiceIntent: AppIntent {
    static var title: LocalizedStringResource { "Set thermostat option" }
    static var isDiscoverable: Bool { false }
    static var openAppWhenRun: Bool { false }
    @Parameter(title: "Kind") var kind: String
    @Parameter(title: "Option") var option: String
    @Parameter(title: "Thermostat") var entityID: String
    @Parameter(title: "Account scope") var scope: String
    @Parameter(title: "Control revision") var revision: String
    @Parameter(title: "Selection revision") var selectionRevision: String
    init() { kind = ""; option = ""; entityID = ""; scope = ""; revision = ""; selectionRevision = "" }
    init(_ kind: String, option: String, entityID: String, scope: String, revision: String,
         selectionRevision: String) {
        self.kind = kind; self.option = option; self.entityID = entityID; self.scope = scope
        self.revision = revision; self.selectionRevision = selectionRevision
    }
    @MainActor func perform() async throws -> some IntentResult {
        ThermostatInlinePickerOpening.retire()
        // Every exit redraws the row as it now is: closed after a choice, untouched for a chip of a replaced row.
        defer { ThermostatInlinePickerStore.reloadWidget() }
        guard let record = ThermostatInlinePickerStore.load(),
              let selection = thermostatInlineSelection(record: record, now: .now, kind: kind, option: option,
                  entityID: entityID, scope: scope, revision: revision, selectionRevision: selectionRevision)
        else { return .result() }
        ThermostatInlinePickerStore.clear()
        guard case .apply(let chosen) = selection,
              thermostatInlinePickerOwned(record, by: HaConfigStore.context()) else { return .result() }
        // The in-app picker's path (`ClimateGate.choose`): the journal transaction re-checks scope,
        // thermostat, control revision and selection before the live read and the command.
        try await ClimateActionRuntime.perform(scope: record.scope, entityID: record.entityID,
            revision: record.revision, resumeID: "", action: record.kind, option: chosen,
            selectionRevision: record.selectionRevision, expectedMode: record.expectedMode)
        return .result()
    }
}
