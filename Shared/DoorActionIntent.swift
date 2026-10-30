import AppIntents
import Foundation
import WidgetKit
import HearthKit

/// Every direct door control uses the account and selection captured by its rendered card.
struct DoorActionIntent: AppIntent {
    static var title: LocalizedStringResource { "Door action" }
    static var isDiscoverable: Bool { false }

    @Parameter(title: "Entity") var id: String
    @Parameter(title: "Action") var action: String
    @Parameter(title: "Account scope") var scope: String
    @Parameter(title: "Door selection") var revision: String
    @Parameter(title: "Operation being stopped", default: "") var replacingOperation: String

    init() {}
    init(scope: String, revision: String, id: String, action: DoorAction, replacingOperation: String = "") {
        self.scope = scope; self.revision = revision; self.id = id; self.action = action.rawValue
        self.replacingOperation = replacingOperation
    }

    func perform() async throws -> some IntentResult {
        try await DoorActionRuntime.perform(scope: scope, revision: revision, entityID: id, action: action,
            replacingOperation: replacingOperation)
        return .result()
    }
}

enum DoorActionRuntime {
    private static func notify() async {
        WidgetCenter.shared.reloadTimelines(ofKind: "com.rohit.hearth.doors")
        await MainActor.run { RefreshSignal.shared.bump() }
    }

    static func perform(scope: String, revision: String, entityID: String, action: String,
                        replacingOperation: String = "") async throws {
        guard !scope.isEmpty, !revision.isEmpty, !entityID.isEmpty,
              let store = HaConfigStore.store else { return }
        _ = try store.expireDoorOperation()
        guard let started = try store.beginDoorOperation(expectedScope: scope, expectedRevision: revision,
                entityID: entityID, action: action,
                replacingID: replacingOperation.isEmpty ? nil : replacingOperation), let config = started.config,
              let operation = started.doorOperation else { return }
        await notify()
        let client = HaClient(config)
        let isCurrent: @Sendable () -> Bool = {
            guard let current = HaConfigStore.context(), current.scope == scope,
                  current.doorActionRevision == operation.actionRevision, haSameConnection(current.config, config),
                  current.config.map({ doorsSelectedIDs($0).contains(entityID) }) == true,
                  let active = current.doorOperation, active.id == operation.id, active.pending else { return false }
            let age = Date().timeIntervalSince(active.startedAt)
            return age >= 0 && age <= 90
        }
        do {
            let outcome = try await executeDoorAction(entityID: entityID, action: action,
                ownedStopTakeover: action == "stop" && !replacingOperation.isEmpty,
                isCurrent: isCurrent,
                claimDispatch: {
                    try store.claimDoorDispatch(expectedScope: scope, operationID: operation.id) != nil
                },
                read: {
                    let json = try await client.stateJson(entityID)
                    // The executor validates identity/freshness and distinguishes owned Stop preflight
                    // from its strict known-state confirmation; no cached fallback enters this path.
                    return HaStateReading(entityID: entityID, json: json, checkedAt: .now)
                },
                send: { command in
                    guard isCurrent() else { throw HaError("Configuration changed · Refresh to check") }
                    try await client.callService(domain: command.domain, service: command.service,
                        entityId: command.entityID, isAuthorized: isCurrent,
                        serviceGate: store.doorServiceGate(entityID: command.entityID))
                },
                observe: { reading in
                    guard try store.observeDoorOperation(expectedScope: scope, operationID: operation.id,
                            reading: reading) != nil else { return }
                    await notify()
                },
                wait: { try await Task.sleep(for: .seconds(2)) })
            switch outcome {
            case .confirmed:
                _ = try store.finishDoorOperation(expectedScope: scope, operationID: operation.id, error: nil)
            case .obsolete:
                _ = try store.finishDoorOperation(expectedScope: scope, operationID: operation.id,
                    error: "Update interrupted · Refresh to check")
            case .rejected: throw HaError("Action no longer available · Refresh to check")
            case .unconfirmed: throw HaError("Couldn't confirm · Refresh to check")
            }
            await notify()
        } catch {
            let message = error is CancellationError ? "Update interrupted · Refresh to check" : friendlyError(error)
            let settled = try store.finishDoorOperation(expectedScope: scope, operationID: operation.id, error: message)
            await notify()
            guard settled != nil else { return }
            throw HaError(message)
        }
    }
}
