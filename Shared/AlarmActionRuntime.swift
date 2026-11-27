import Foundation
import WidgetKit
import HearthKit

enum AlarmActionRuntime {
    private static func notify() async {
        WidgetCenter.shared.reloadTimelines(ofKind: "com.rohit.hearth.alarm")
        await MainActor.run { RefreshSignal.shared.bump() }
    }

    static func perform(
        scope: String,
        revision: String,
        entityID: String,
        action: String,
        injectedRecord: (@Sendable (ActionHistoryRecord) -> Void)? = nil
    ) async throws {
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
                await notify()

                // Record action history (Routines learning hook).
                // This runs AFTER the operation is confirmed and finished, and must NEVER delay or throw.
                // Capture entityID and action before the closure (Sendable compliance).
                let entityIDCaptured = entityID
                let actionCaptured = action
                let now = Date()
                let sourceKey = "alarm.\(actionCaptured)"  // e.g., "alarm.armNight", "alarm.disarm"
                let entry = ActionHistoryRecord(timestamp: now, entityIDs: [entityIDCaptured], sourceKey: sourceKey)

                if let record = injectedRecord {
                    // Test path: call injected spy
                    record(entry)
                } else {
                    // Production path: record to ActionHistoryStore.
                    // Swallow any recording failure (best-effort local UserDefaults).
                    ActionHistoryStore.record(entry, now: now)
                }
            case .obsolete:
                _ = try store.finishAlarmOperation(expectedScope: scope, operationID: operation.id,
                    error: "Update interrupted · Refresh to check")
                await notify()
            case .rejected:
                // Safety monitoring: retry in background if enabled
                if HouseFeaturesStore.safetyEnabled {
                    Task {
                        await safetyRetry(config: config, entityID: entityID, action: action, scope: scope, isCurrent: isCurrent)
                    }
                }
                throw HaError("Action no longer available · Refresh to check")
            case .unconfirmed:
                // Safety monitoring: retry in background if enabled
                if HouseFeaturesStore.safetyEnabled {
                    Task {
                        await safetyRetry(config: config, entityID: entityID, action: action, scope: scope, isCurrent: isCurrent)
                    }
                }
                throw HaError("Couldn't confirm · Refresh to check")
            }
        } catch {
            let message = error is CancellationError ? "Update interrupted · Refresh to check" : friendlyError(error)
            _ = try store.finishAlarmOperation(expectedScope: scope, operationID: operation.id, error: message)
            await notify()
            throw HaError(message)
        }
    }

    /// Safety monitoring: retry alarm/lock action with monitorWithRetry and post notification on final failure.
    ///
    /// This is called in a background Task when safety alerts are enabled and the first attempt
    /// returns .unconfirmed or .rejected. It's purely additive — the original error is still thrown
    /// to the UI, but we do one more retry in the background and notify if it still fails.
    ///
    /// - Parameters:
    ///   - config: Home Assistant config
    ///   - entityID: Entity to control
    ///   - action: Action to perform (e.g., "lock", "armHome")
    ///   - scope: Config scope for validation
    ///   - isCurrent: Closure to check if the operation is still valid
    private static func safetyRetry(config: HaConfig, entityID: String, action: String,
                                   scope: String, isCurrent: @Sendable @escaping () -> Bool) async {
        let client = HaClient(config)
        let executor = AlarmActionExecutor(
            config: config,
            client: client,
            entityID: entityID,
            action: action,
            isCurrent: isCurrent
        )

        await monitorWithRetry(executor) {
            // Final failure: post safety notification (only if still current)
            guard isCurrent() else { return }
            let deviceName = friendlyDeviceName(entityID: entityID)
            let targetState = friendlyTargetState(action: action)
            let title = "\(deviceName) won't \(targetState)"
            let body = "Tap to check"
            HouseNotify.postImmediate(
                id: "safety-\(entityID)-\(action)",
                title: title,
                body: body
            )
        }
    }

    private static func friendlyDeviceName(entityID: String) -> String {
        if entityID.hasPrefix("lock.") {
            let name = entityID.dropFirst("lock.".count)
            return name.replacingOccurrences(of: "_", with: " ").capitalized
        }
        if entityID.hasPrefix("alarm_control_panel.") {
            return "Home alarm"
        }
        return "Device"
    }

    private static func friendlyTargetState(action: String) -> String {
        switch action {
        case "lock": return "lock"
        case "unlock": return "unlock"
        case "armHome": return "arm (Home)"
        case "armAway": return "arm (Away)"
        case "armNight": return "arm (Night)"
        case "disarm": return "disarm"
        default: return "update"
        }
    }
}

/// ActionExecutor implementation for alarm/lock actions.
/// Used by safety monitoring to retry failed actions.
private struct AlarmActionExecutor: ActionExecutor {
    let config: HaConfig
    let client: HaClient
    let entityID: String
    let action: String
    let isCurrent: @Sendable () -> Bool

    func execute() async throws {
        // Execute and verify are combined in executeAlarmAction, so we just call it
        // with a short retry count (1 attempt) and discard the result here.
        // The actual verification happens in verify().
        _ = try? await executeAlarmAction(
            entityID: entityID,
            action: action,
            isCurrent: isCurrent,
            read: { try await readState() },
            send: { command in
                guard isCurrent() else { throw HaError("Configuration changed") }
                try await client.callService(domain: command.domain, service: command.service,
                                           entityId: command.entityID, isAuthorized: isCurrent)
            },
            wait: { try await Task.sleep(for: .seconds(2)) },
            confirmationAttempts: 1
        )
    }

    func verify() async throws -> Bool {
        // Read the current state and check if it matches the target
        let reading = try await readState()
        guard let state = alarmObservation(reading, entityID: entityID) else { return false }

        // Determine the target state for this action
        if entityID.hasPrefix("alarm_control_panel."), let alarmAction = AlarmAction(rawValue: action) {
            return state.state == alarmAction.target
        }
        if entityID.hasPrefix("lock."), let lockAction = LockAction(rawValue: action) {
            return state.state == lockAction.target
        }
        return false
    }

    private func readState() async throws -> HaStateReading {
        let read = await fetchHaStateReadings(config, ids: [entityID]) { id in
            let json = try await client.stateJson(id)
            guard AlarmState.fromJson(json)?.entityID == id else {
                throw HaError("Couldn't read the selected device")
            }
            return json
        }
        if let message = read.errors[entityID] {
            throw HaError(message)
        }
        guard let value = read.readings[entityID] else {
            throw HaError("Couldn't read the selected device")
        }
        return value
    }
}
