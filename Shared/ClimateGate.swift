import SwiftUI
import HearthKit

struct ClimatePick: Identifiable, Sendable {
    let id = UUID()
    let kind: String
    let options: [String]
    let current: String?
    let scope: String
    let entityID: String
    let revision: String
    let selection: ThermostatSelectionOrigin
    let expectedMode: String?
    let lifetime: ThermostatRequestLifetime
    var title: String { kind == "fan" ? "Fan mode" : "Mode" }
}
struct ClimatePickerPresentation: Sendable {
    let id: UUID
    let lifetime: ThermostatRequestLifetime
}

/// Choices keep the selection/revision that advertised them; replacing a picker retires its callbacks.
@MainActor final class ClimateGate: ObservableObject {
    static let shared = ClimateGate()
    private let dependencies: ClimateActionDependencies?
    private var lifetime: ThermostatRequestLifetime?
    private var actionID: UUID?
    private var presentationID: UUID?
    init(dependencies: ClimateActionDependencies? = nil) { self.dependencies = dependencies }
    @Published var pick: ClimatePick?
    @Published var error: String?
    private var context: HaStoreSnapshot? {
        if let dependencies { return try? dependencies.store?.snapshot() }
        return HaConfigStore.context()
    }
    func reservePresentation() -> ClimatePickerPresentation {
        retire()
        let id = UUID(); presentationID = id
        let lifetime = ThermostatRequestLifetime(); self.lifetime = lifetime
        return ClimatePickerPresentation(id: id, lifetime: lifetime)
    }
    func presentationCurrent(_ id: UUID) -> Bool {
        presentationID == id && lifetime?.isActive() == true
    }
    func present(kind: String, options: [String], current: String?, scope: String, entityID: String,
                 revision: String, selectionRevision: String = "", expectedMode: String? = nil,
                 presentationID: UUID? = nil) {
        if let presentationID, !presentationCurrent(presentationID) { return }
        lifetime?.invalidate(); actionID = nil; pick = nil; error = nil
        self.presentationID = nil
        guard let context, context.scope == scope, context.config?.climateId == entityID,
              let selection = ThermostatSelectionOrigin(context),
              selectionRevision.isEmpty || selectionRevision == selection.selectionRevision else { return }
        let lifetime = ThermostatRequestLifetime(); self.lifetime = lifetime
        pick = ClimatePick(kind: kind, options: options, current: current,
            scope: scope, entityID: entityID, revision: revision, selection: selection,
            expectedMode: expectedMode, lifetime: lifetime)
    }
    @discardableResult func choose(_ request: ClimatePick, _ option: String) -> Task<Void, Never>? {
        guard pick?.id == request.id, request.options.contains(option), request.lifetime.isActive(),
              let context, request.selection.matches(context) else { return nil }
        pick = nil
        let id = UUID(); actionID = id
        let issues = ClimateLocalIssueRecord()
        return Task {
            do {
                try await ClimateActionRuntime.perform(scope: request.scope, entityID: request.entityID,
                    revision: request.revision, resumeID: "", action: request.kind, option: option,
                    selectionRevision: request.selection.selectionRevision, expectedMode: request.expectedMode,
                    actionID: id, isAuthorized: { request.lifetime.isActive() },
                    onLocalIssue: { issues.record($0.phase) }, dependencies: dependencies)
            } catch {
                guard actionID == id, request.lifetime.isActive(), let current = self.context,
                      request.selection.matches(current) else { return }
                if let phase = issues.phase { self.error = climateLocalIssueMessage(phase) }
                else if let failure = error as? ClimateActionFailure {
                    guard current.climateOperation?.id == failure.operationID else { return }
                    self.error = failure.message
                } else { self.error = friendlyError(error) }
            }
        }
    }
    func dismiss() {
        if pick != nil { lifetime?.invalidate(); actionID = nil }
        pick = nil
    }
    func retire() { lifetime?.invalidate(); actionID = nil; presentationID = nil; pick = nil; error = nil }
}
