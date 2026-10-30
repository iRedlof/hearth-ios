import Foundation
import HearthKit

enum ThermostatLiveSnapshot {
    static func selectionMatches(_ a: HaConfig?, _ b: HaConfig?) -> Bool {
        a?.climateId == b?.climateId && a?.sensorIds == b?.sensorIds && a?.resumeId == b?.resumeId
    }
    static func fetch(now: Date = .now) async -> ThermostatSnapshot {
        guard let context = try? HaConfigStore.climateContext(now: now) else { return storageUnavailable(now: now) }
        // Begin feedback must render before any network wait, even when HA is offline.
        if context.climateOperation?.pending == true { return cached(context, now: now, error: nil) }
        let scope = context.scope, config = context.config
        let result = await fetchThermostatReadings(config, previous: context.readings, now: now)
        // Merge per entity; an older overlapping read cannot replace a newer successful reading.
        let merged: HaStoreSnapshot
        do {
            guard let accepted = try HaReadingsStore.merge(result.readings, scope: scope,
                    climateRevision: context.climateRevision, failures: result.errors, checkedAt: now),
                  selectionMatches(config, accepted.config) else {
                return cached(now: now, error: "Configuration changed · Refresh to check")
            }
            merged = accepted
        } catch {
            return cached(now: now, error: "Can't save readings · Refresh to retry")
        }
        let current = merged.readings
        let errors = merged.failures.mapValues(\.message)
        let snapshot = ThermostatFetchResult(entityID: result.entityID, sensorIDs: result.sensorIDs,
            readings: current, errors: errors, setup: result.setup, resumeID: result.resumeID).snapshot(now: now)
        return bound(snapshot, context: merged)
    }
    /// Reconcile again at the display sink after a concurrent app/widget refresh.
    static func currentFeedback(_ snapshot: ThermostatSnapshot, now: Date = .now) -> ThermostatSnapshot {
        guard let context = try? HaConfigStore.climateContext(now: now) else { return storageUnavailable(now: now) }
        return thermostatCurrentFeedback(snapshot, context: context, now: now)
    }
    private static func cached(now: Date, error: String) -> ThermostatSnapshot {
        guard let context = HaConfigStore.context() else { return storageUnavailable(now: now) }
        return cached(context, now: now, error: error)
    }
    private static func cached(_ context: HaStoreSnapshot, now: Date, error: String?) -> ThermostatSnapshot {
        thermostatStoredSnapshot(context, now: now, transientError: error)
    }
    private static func bound(_ snapshot: ThermostatSnapshot, context: HaStoreSnapshot) -> ThermostatSnapshot {
        var result = snapshot
        result.requestScope = context.scope
        result.climateRevision = context.climateRevision
        return climateApplyingOperation(result, context.climateOperation)
    }
    private static func storageUnavailable(now: Date) -> ThermostatSnapshot {
        var snapshot = ThermostatFetchResult(setup: true).snapshot(now: now)
        snapshot.status = "Can't read settings"
        snapshot.error = "Shared storage is unavailable. Please reopen Hearth."
        return snapshot
    }
}
