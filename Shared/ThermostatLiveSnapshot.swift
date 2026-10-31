import Foundation
import HearthKit

enum ThermostatLiveSnapshot {
    static func selectionMatches(_ a: HaConfig?, _ b: HaConfig?) -> Bool {
        a?.climateId == b?.climateId && a?.sensorIds == b?.sensorIds && a?.resumeId == b?.resumeId
    }
    private static func loader(request: (@Sendable (String) async throws -> String)? = nil) -> ThermostatLiveLoader {
        ThermostatLiveLoader(load: { try HaConfigStore.climateContext(now: $0) },
            merge: { result, origin, revision, now in
                try HaReadingsStore.merge(result.readings, scope: origin?.scope ?? "",
                    climateRevision: revision, failures: result.errors, checkedAt: now,
                    thermostatSelectionRevision: origin?.selectionRevision, failureReasons: result.failureReasons)
            }, request: request)
    }
    static func fetch(now: Date = .now) async -> ThermostatSnapshot {
        await fetchEnvelope(now: now).snapshot
    }
    static func fetchEnvelope(now: Date = .now,
                              request: (@Sendable (String) async throws -> String)? = nil) async -> ThermostatLiveEnvelope {
        await loader(request: request).fetch(now: now)
    }
    static func currentEnvelope(_ envelope: ThermostatLiveEnvelope, now: Date = .now) -> ThermostatLiveEnvelope {
        loader().currentEnvelope(envelope, now: now)
    }
    static func currentFeedback(_ snapshot: ThermostatSnapshot, now: Date = .now) -> ThermostatSnapshot {
        guard let evidence = snapshot.evidence else { return thermostatStorageUnavailableEnvelope(now: now).snapshot }
        return currentEnvelope(ThermostatLiveEnvelope(evidence: evidence, now: now), now: now).snapshot
    }
}
