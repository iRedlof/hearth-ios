import Foundation

/// Build telemetry, selected rows, and command feedback from one coherent shared-store read.
public func thermostatStoredSnapshot(_ context: HaStoreSnapshot, now: Date = .now,
                                     transientError: String? = nil,
                                     zone: TimeZone = .current, locale: Locale = .current) -> ThermostatSnapshot {
    let result: ThermostatFetchResult
    if let config = context.config, config.hasClimate {
        var errors = context.failures.mapValues(\.message)
        if let transientError { errors[config.climateId] = transientError }
        var seen = Set<String>()
        let sensors = Array(config.sensorIds.filter { !$0.isEmpty && seen.insert($0).inserted }.prefix(3))
        result = ThermostatFetchResult(entityID: config.climateId, sensorIDs: sensors,
            readings: context.readings, errors: errors, resumeID: config.resumeId)
    } else {
        result = ThermostatFetchResult(setup: true)
    }
    var snapshot = result.snapshot(now: now, zone: zone, locale: locale)
    // Legacy transient copy stays formatting-only; new recovery comes from the actual loader branch.
    snapshot.evidence = thermostatEnvelope(context, now: now).evidence
    snapshot.requestScope = context.scope
    snapshot.climateRevision = context.climateRevision
    return climateApplyingOperation(snapshot, context.climateOperation)
}

/// Reconcile at the display sink after another process may have updated shared state.
public func thermostatCurrentFeedback(_ snapshot: ThermostatSnapshot, context: HaStoreSnapshot,
                                      now: Date = .now, zone: TimeZone = .current,
                                      locale: Locale = .current) -> ThermostatSnapshot {
    let sameBinding = snapshot.requestScope == context.scope
        && snapshot.climateRevision == context.climateRevision
        && snapshot.entityID == context.config?.climateId
    // Readings and selected sensors can change without rotating the command revision.
    // Only local storage feedback is transient; HA failures are authoritative in the store.
    let transientErrors = ["Can't save readings · Refresh to retry",
                           "Configuration changed · Refresh to check"]
    let transientError = sameBinding && snapshot.error.map(transientErrors.contains) == true
        ? snapshot.error : nil
    return thermostatStoredSnapshot(context, now: now, transientError: transientError,
                                    zone: zone, locale: locale)
}
