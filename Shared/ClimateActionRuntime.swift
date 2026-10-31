import Foundation
import WidgetKit
import HearthKit

struct ClimateActionFailure: LocalizedError, Sendable {
    let operationID: String
    let message: String
    var errorDescription: String? { message }
}

enum ClimateActionRuntime {
    static func current(scope: String, entityID: String, revision: String? = nil,
                        operationID: String? = nil, resumeID: String? = nil, config: HaConfig?) -> Bool {
        guard !scope.isEmpty, !entityID.isEmpty, let config, config.hasClimate,
              let current = HaConfigStore.context(), current.scope == scope,
              haSameConnection(current.config, config),
              current.config?.climateId == entityID, config.climateId == entityID else { return false }
        if let revision, current.climateRevision != revision { return false }
        if let operationID {
            guard let operation = current.climateOperation, operation.id == operationID, operation.pending,
                  Date().timeIntervalSince(operation.startedAt) <= 90 else { return false }
        } else if current.climateOperation?.pending == true { return false }
        return resumeID == nil || current.config?.resumeId == resumeID
    }
    static func read(_ config: HaConfig) async throws -> ClimateState? {
        let result = await fetchHaStateReadings(config, ids: [config.climateId])
        if let error = result.errors[config.climateId] { throw HaError(error) }
        return result.readings[config.climateId].flatMap { ClimateState.fromJson($0.json) }
    }
    private static func notify() async {
        WidgetCenter.shared.reloadTimelines(ofKind: "com.rohit.hearth.thermostat")
        await MainActor.run { RefreshSignal.shared.bump() }
    }
    static func perform(scope: String, entityID: String, revision: String, resumeID: String,
                        action: String, option: String? = nil) async throws {
        guard !revision.isEmpty, let store = HaConfigStore.store else { return }
        let boundResume = action == "resume" ? resumeID : nil
        _ = try store.expireClimateOperation()
        guard let started = try store.beginClimateOperation(expectedScope: scope, expectedRevision: revision,
                  entityID: entityID, action: action, resumeID: boundResume),
              let config = started.config, let operation = started.climateOperation else { return }
        await notify()
        let client = HaClient(config)
        do {
            _ = try await executeClimateAction(entityID: entityID, action: action, resumeID: resumeID, option: option,
                isCurrent: { current(scope: scope, entityID: entityID, operationID: operation.id,
                    resumeID: boundResume, config: config) },
                read: { try await read(config) },
                send: { command in
                    var data = command.temperatures.mapValues { $0 as Any }
                    if let key = command.optionKey, let value = command.option { data[key] = value }
                    try await client.callService(domain: command.domain, service: command.service,
                        entityId: command.entityID, data: data,
                        isAuthorized: {
                            current(scope: scope, entityID: entityID, operationID: operation.id,
                                resumeID: boundResume, config: config)
                        })
                })
            _ = try store.finishClimateOperation(expectedScope: scope, operationID: operation.id, error: nil)
            await notify()
        } catch {
            let message = error is CancellationError ? "Update interrupted · Refresh to check" : friendlyError(error)
            let settled: HaStoreSnapshot?
            do {
                settled = try store.finishClimateOperation(expectedScope: scope, operationID: operation.id,
                    error: message, failureKind: error is CancellationError ? .interrupted : .generic)
            } catch {
                await notify()
                throw error
            }
            await notify()
            guard settled != nil else { return }
            throw ClimateActionFailure(operationID: operation.id, message: message)
        }
    }
}
