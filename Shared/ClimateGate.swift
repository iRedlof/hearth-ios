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
    var title: String { kind == "fan" ? "Fan mode" : "Mode" }
}

/// App choices retain the widget's entity/account binding until the selected command dispatches.
@MainActor final class ClimateGate: ObservableObject {
    static let shared = ClimateGate()
    private init() {}
    @Published var pick: ClimatePick?
    @Published var error: String?
    func present(kind: String, options: [String], current: String?, scope: String, entityID: String, revision: String) {
        error = nil
        pick = ClimatePick(kind: kind, options: options, current: current,
            scope: scope, entityID: entityID, revision: revision)
    }
    func choose(_ request: ClimatePick, _ option: String) {
        guard pick?.id == request.id, request.options.contains(option) else { return }
        pick = nil
        Task {
            do {
                try await ClimateActionRuntime.perform(scope: request.scope, entityID: request.entityID,
                    revision: request.revision, resumeID: "", action: request.kind, option: option)
            } catch let failure as ClimateActionFailure {
                guard let current = HaConfigStore.context(), current.scope == request.scope,
                      current.config?.climateId == request.entityID,
                      current.climateOperation?.id == failure.operationID else { return }
                self.error = failure.message
            } catch {
                guard let current = HaConfigStore.context(), current.scope == request.scope,
                      current.config?.climateId == request.entityID else { return }
                self.error = friendlyError(error)
            }
        }
    }
    func dismiss() { pick = nil }
}
