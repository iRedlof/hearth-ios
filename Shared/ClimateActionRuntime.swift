import Foundation
import WidgetKit
import HearthKit

struct ClimateActionFailure: LocalizedError, Sendable {
    let operationID: String
    let message: String
    var errorDescription: String? { message }
}

/// Local write attribution carries no command or provider acknowledgement.
final class ClimateLocalIssueRecord: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: ClimateOperationPersistencePhase?
    var phase: ClimateOperationPersistencePhase? { lock.withLock { stored } }
    func record(_ phase: ClimateOperationPersistencePhase) { lock.withLock { stored = phase } }
}
func climateLocalIssueMessage(_ phase: ClimateOperationPersistencePhase) -> String {
    phase == .beginSave ? "Couldn't save update. No command was sent." : "Couldn't save update. Refresh to check your thermostat."
}

/// Ownership of a local settlement, never acknowledgement of a provider outcome.
struct ClimateSettlementReceipt: Sendable {
    let actionID: UUID
    let selection: ThermostatSelectionOrigin
    let operationID: String
    let context: HaStoreSnapshot
}

/// The existing runtime's small transport seam; production keeps its guarded HaClient and journal.
struct ClimateActionDependencies: Sendable {
    let store: HaStateStore?
    let read: @Sendable (HaConfig, @escaping @Sendable () -> Bool) async throws -> ClimateState?
    let send: @Sendable (HaConfig, ClimateCommand, @escaping @Sendable () -> Bool) async throws -> Void
    let notify: @Sendable () async -> Void
    let followup: @Sendable (ClimateSettlementReceipt, @escaping @Sendable () -> Bool) async -> Void
    let clock: @Sendable () -> Date

    static var live: Self {
        Self(store: HaConfigStore.store,
            read: { config, authorized in try await ClimateActionRuntime.read(config, isAuthorized: authorized) },
            send: { config, command, authorized in
                var data = command.temperatures.mapValues { $0 as Any }
                if let key = command.optionKey, let value = command.option { data[key] = value }
                try await HaClient(config).callService(domain: command.domain, service: command.service,
                    entityId: command.entityID, data: data, isAuthorized: authorized)
            }, notify: { await ClimateActionRuntime.notify() }, followup: { receipt, authorized in
                guard authorized() else { return }
                _ = await ThermostatLiveSnapshot.fetchEnvelope(expectedSelection: receipt.selection,
                    owner: ThermostatReadOwner(id: receipt.actionID, source: .commandSettlement),
                    previous: thermostatEnvelope(receipt.context), isAuthorized: authorized)
            }, clock: { .now })
    }
}

enum ClimateActionRuntime {
    static func current(scope: String, entityID: String, revision: String? = nil,
                        operationID: String? = nil, resumeID: String? = nil, config: HaConfig?,
                        selectionRevision: String? = nil) -> Bool {
        guard let current = HaConfigStore.context(), !scope.isEmpty, !entityID.isEmpty,
              let config, config.hasClimate, current.scope == scope,
              haSameConnection(current.config, config), current.config?.climateId == entityID,
              config.climateId == entityID else { return false }
        if let selectionRevision, current.thermostatSelectionRevision != selectionRevision { return false }
        if let revision, current.climateRevision != revision { return false }
        if let operationID {
            guard let operation = current.climateOperation, operation.id == operationID, operation.pending,
                  operation.entityID == entityID else { return false }
            let age = Date().timeIntervalSince(operation.startedAt)
            guard age.isFinite, (0...90).contains(age) else { return false }
        } else if current.climateOperation?.pending == true { return false }
        return resumeID == nil || current.config?.resumeId == resumeID
    }
    static func read(_ config: HaConfig, isAuthorized: (@Sendable () -> Bool)? = nil,
                     request: (@Sendable (String) async throws -> String)? = nil) async throws -> ClimateState? {
        guard isAuthorized?() != false else { throw CancellationError() }
        let json: String
        if let request { json = try await request(config.climateId) }
        else { json = try await HaClient(config).stateJson(config.climateId, isAuthorized: isAuthorized) }
        guard isAuthorized?() != false else { throw CancellationError() }
        guard let data = json.data(using: .utf8),
              let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let state = object["state"] as? String, !state.isEmpty,
              object["entity_id"] == nil || object["entity_id"] as? String == config.climateId else {
            throw HaError("Couldn't read climate data")
        }
        return ClimateState.fromJson(json)
    }
    static func notify() async {
        WidgetCenter.shared.reloadTimelines(ofKind: "com.rohit.hearth.thermostat")
        await MainActor.run { RefreshSignal.shared.bump() }
    }
    static func perform(scope: String, entityID: String, revision: String, resumeID: String,
                        action: String, option: String? = nil, selectionRevision: String = "", expectedMode: String? = nil,
                        actionID: UUID = UUID(), isAuthorized: @escaping @Sendable () -> Bool = { true },
                        onLocalIssue: @escaping @Sendable (ClimateOperationPersistenceFailure) -> Void = { _ in },
                        dependencies: ClimateActionDependencies? = nil) async throws {
        let dependencies = dependencies ?? .live
        guard !revision.isEmpty, isAuthorized(), !Task.isCancelled, let store = dependencies.store,
              selectionRevision.isEmpty || UUID(uuidString: selectionRevision) != nil else { return }
        let directional = ["heatUp", "heatDown", "coolUp", "coolDown"].contains(action)
        guard selectionRevision.isEmpty || !directional || expectedMode?.isEmpty == false else { return }
        let before = try store.expireClimateOperation(now: dependencies.clock())
        guard before.scope == scope, before.config?.climateId == entityID,
              let selection = ThermostatSelectionOrigin(before),
              selectionRevision.isEmpty || selection.selectionRevision == selectionRevision else { return }
        let boundResume = action == "resume" ? resumeID : nil
        let started: HaStoreSnapshot?
        do {
            started = try store.beginClimateOperation(expectedScope: scope, expectedRevision: revision,
                entityID: entityID, action: action, resumeID: boundResume, now: dependencies.clock(),
                expectedThermostatSelectionRevision: selection.selectionRevision)
        } catch let failure as ClimateOperationPersistenceFailure {
            if isAuthorized(), (try? store.snapshot()).map(selection.matches) == true { onLocalIssue(failure) }
            throw failure.underlying
        }
        guard let started, let config = started.config, let operation = started.climateOperation else { return }
        let pendingAuthorized: @Sendable () -> Bool = {
            guard !Task.isCancelled, isAuthorized(), let current = try? store.snapshot(), selection.matches(current),
                  let pending = current.climateOperation, pending.id == operation.id,
                  pending.entityID == entityID, pending.action == action, pending.pending else { return false }
            let age = dependencies.clock().timeIntervalSince(pending.startedAt)
            return age.isFinite && (0...90).contains(age)
                && (boundResume == nil || current.config?.resumeId == boundResume)
        }
        await dependencies.notify()
        var executionError: (any Error)?
        do {
            _ = try await executeClimateAction(entityID: entityID, action: action, resumeID: resumeID, option: option,
                expectedMode: expectedMode, isCurrent: pendingAuthorized,
                read: { try await dependencies.read(config, pendingAuthorized) },
                send: { try await dependencies.send(config, $0, pendingAuthorized) })
        } catch { executionError = error }
        // A replaced selection/owner cannot settle into today's journal or publish a callback.
        guard isAuthorized(), let current = try? store.snapshot(), selection.matches(current),
              current.climateOperation?.id == operation.id, current.climateOperation?.pending == true else { return }
        let message = executionError.map { $0 is CancellationError ? "Update interrupted · Refresh to check" : friendlyError($0) }
        let settled: HaStoreSnapshot?
        do {
            settled = try store.finishClimateOperation(expectedScope: scope, operationID: operation.id,
                error: message, failureKind: executionError is CancellationError ? .interrupted : .generic,
                expectedThermostatSelectionRevision: selection.selectionRevision)
        } catch let failure as ClimateOperationPersistenceFailure {
            if isAuthorized(), (try? store.snapshot()).map(selection.matches) == true { onLocalIssue(failure) }
            await dependencies.notify()
            throw failure.underlying
        }
        await dependencies.notify()
        guard let settled, selection.matches(settled) else { return }
        let settledAuthorized: @Sendable () -> Bool = {
            guard !Task.isCancelled, isAuthorized(), let context = try? store.snapshot(), selection.matches(context),
                  context.climateRevision == settled.climateRevision, context.climateOperation?.pending != true else { return false }
            return dependencies.clock().timeIntervalSince(operation.startedAt).isFinite
                && (0...90).contains(dependencies.clock().timeIntervalSince(operation.startedAt))
        }
        if settledAuthorized() {
            await dependencies.followup(ClimateSettlementReceipt(actionID: actionID, selection: selection,
                operationID: operation.id, context: settled), settledAuthorized)
            await dependencies.notify()
        }
        if let message, isAuthorized(), (try? store.snapshot()).map(selection.matches) == true {
            throw ClimateActionFailure(operationID: operation.id, message: message)
        }
    }
}
