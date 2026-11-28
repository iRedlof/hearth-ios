import Foundation

/// Telemetry, selected door and garage, both action origins and operation feedback come from one
/// locked store read.
public func alarmStoredSnapshot(_ context: HaStoreSnapshot, now: Date = .now,
                                transientError: String? = nil,
                                zone: TimeZone = .current, locale: Locale = .current) -> AlarmSnapshot {
    let result: AlarmFetchResult
    if let config = context.config, config.isComplete {
        let garageID = garageSelectedID(config) ?? ""
        var errors = context.failures.mapValues(\.message)
        let commandFailure = garageCommandFailure(context.doorOperation, entityID: garageID,
                                                  readings: context.readings, failures: context.failures)
        if let transientError {
            errors[config.entityId] = transientError
            if config.hasLock { errors[config.lockId] = transientError }
            if !garageID.isEmpty { errors[garageID] = transientError }
        }
        result = AlarmFetchResult(entityID: config.entityId, lockID: config.hasLock ? config.lockId : "",
            lockName: config.lockName, garageID: garageID, readings: context.readings, errors: errors,
            garageCommandFailure: commandFailure)
    } else { result = AlarmFetchResult(setup: true) }
    var snapshot = result.snapshot(now: now, zone: zone, locale: locale)
    snapshot.requestScope = context.scope
    snapshot.alarmRevision = context.alarmRevision
    return alarmApplyingDoorOperation(alarmApplyingOperation(snapshot, context.alarmOperation),
        context.doorOperation, actionRevision: context.doorActionRevision)
}

/// Readings can change without a command revision changing; always rebuild at the display sink.
public func alarmCurrentFeedback(_ snapshot: AlarmSnapshot, context: HaStoreSnapshot, now: Date = .now,
                                 zone: TimeZone = .current, locale: Locale = .current) -> AlarmSnapshot {
    let sameBinding = snapshot.requestScope == context.scope && snapshot.alarmRevision == context.alarmRevision
        && snapshot.entityID == context.config?.entityId && snapshot.lockID == (context.config?.hasLock == true ? context.config?.lockId : "")
        && snapshot.garage?.entityID == context.config.flatMap(garageSelectedID)
    let transientErrors = ["Can't save readings · Refresh to retry", "Configuration changed · Refresh to check"]
    let error = sameBinding && snapshot.error.map(transientErrors.contains) == true ? snapshot.error : nil
    return alarmStoredSnapshot(context, now: now, transientError: error, zone: zone, locale: locale)
}
