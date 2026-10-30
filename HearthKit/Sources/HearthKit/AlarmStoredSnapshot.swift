import Foundation

/// Telemetry, selected door, action origin and operation feedback come from one locked store read.
public func alarmStoredSnapshot(_ context: HaStoreSnapshot, now: Date = .now,
                                transientError: String? = nil,
                                zone: TimeZone = .current, locale: Locale = .current) -> AlarmSnapshot {
    let result: AlarmFetchResult
    if let config = context.config, config.isComplete {
        var errors = context.failures.mapValues(\.message)
        if let transientError {
            errors[config.entityId] = transientError
            if config.hasLock { errors[config.lockId] = transientError }
        }
        result = AlarmFetchResult(entityID: config.entityId, lockID: config.hasLock ? config.lockId : "",
            lockName: config.lockName, readings: context.readings, errors: errors)
    } else { result = AlarmFetchResult(setup: true) }
    var snapshot = result.snapshot(now: now, zone: zone, locale: locale)
    snapshot.requestScope = context.scope
    snapshot.alarmRevision = context.alarmRevision
    return alarmApplyingOperation(snapshot, context.alarmOperation)
}

/// Readings can change without a command revision changing; always rebuild at the display sink.
public func alarmCurrentFeedback(_ snapshot: AlarmSnapshot, context: HaStoreSnapshot, now: Date = .now,
                                 zone: TimeZone = .current, locale: Locale = .current) -> AlarmSnapshot {
    let sameBinding = snapshot.requestScope == context.scope && snapshot.alarmRevision == context.alarmRevision
        && snapshot.entityID == context.config?.entityId && snapshot.lockID == (context.config?.hasLock == true ? context.config?.lockId : "")
    let transientErrors = ["Can't save readings · Refresh to retry", "Configuration changed · Refresh to check"]
    let error = sameBinding && snapshot.error.map(transientErrors.contains) == true ? snapshot.error : nil
    return alarmStoredSnapshot(context, now: now, transientError: error, zone: zone, locale: locale)
}
