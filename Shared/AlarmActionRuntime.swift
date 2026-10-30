import Foundation
import WidgetKit
import HearthKit

enum AlarmActionRuntime {
    private static func notify() async {
        WidgetCenter.shared.reloadTimelines(ofKind: "com.rohit.hearth.alarm")
        await MainActor.run { RefreshSignal.shared.bump() }
    }

    static func perform(scope: String, revision: String, entityID: String, action: String) async throws {
        guard !scope.isEmpty, !revision.isEmpty, !entityID.isEmpty, let store = HaConfigStore.store else { return }
        _ = try store.expireAlarmOperation()
        guard let started = try store.beginAlarmOperation(expectedScope: scope, expectedRevision: revision,
                entityID: entityID, action: action), let config = started.config,
              let operation = started.alarmOperation else { return }
        await notify()
        let client = HaClient(config)
        let isCurrent: @Sendable () -> Bool = {
            guard let current = HaConfigStore.context(), current.scope == scope,
                  current.alarmRevision == started.alarmRevision,
                  haSameConnection(current.config, config),
                  current.config?.entityId == config.entityId, current.config?.lockId == config.lockId,
                  let active = current.alarmOperation, active.id == operation.id, active.pending,
                  Date().timeIntervalSince(active.startedAt) <= 90 else { return false }
            return true
        }
        do {
            let outcome = try await executeAlarmAction(entityID: entityID, action: action,
                isCurrent: isCurrent,
                read: {
                    let read = await fetchHaStateReadings(config, ids: [entityID]) { id in
                        let json = try await client.stateJson(id)
                        guard AlarmState.fromJson(json)?.entityID == id else { throw HaError("Couldn't read the selected device") }
                        return json
                    }
                    if let message = read.errors[entityID] {
                        _ = try store.failAlarmOperationRead(expectedScope: scope, operationID: operation.id, message: message)
                        throw HaError(message)
                    }
                    guard let value = read.readings[entityID] else { throw HaError("Couldn't read the selected device") }
                    return value
                },
                send: { command in
                    // Final origin check before this sole service call; never resolves a new selection.
                    guard isCurrent() else { throw HaError("Configuration changed · Refresh to check") }
                    try await client.callService(domain: command.domain, service: command.service,
                        entityId: command.entityID, isAuthorized: isCurrent)
                },
                observe: { reading in
                    guard let accepted = try store.observeAlarmOperation(expectedScope: scope,
                            operationID: operation.id, reading: reading),
                          accepted.alarmRevision == started.alarmRevision else { return }
                    await notify()
                },
                wait: { try await Task.sleep(for: .seconds(2)) })
            switch outcome {
            case .confirmed:
                _ = try store.finishAlarmOperation(expectedScope: scope, operationID: operation.id, error: nil)
            case .obsolete:
                _ = try store.finishAlarmOperation(expectedScope: scope, operationID: operation.id,
                    error: "Update interrupted · Refresh to check")
            case .rejected:
                throw HaError("Action no longer available · Refresh to check")
            case .unconfirmed:
                throw HaError("Couldn't confirm · Refresh to check")
            }
            await notify()
        } catch {
            let message = error is CancellationError ? "Update interrupted · Refresh to check" : friendlyError(error)
            _ = try store.finishAlarmOperation(expectedScope: scope, operationID: operation.id, error: message)
            await notify()
            throw HaError(message)
        }
    }
}
