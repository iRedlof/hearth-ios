import Foundation
import HearthKit

/// Per-entity merges and configuration rotation use the same cross-process transaction.
enum HaReadingsStore {
    static func load(scope: String) -> [String: HaStateReading] {
        guard let saved = HaConfigStore.context(), saved.scope == scope else { return [:] }
        return saved.readings
    }
    static func merge(_ readings: [String: HaStateReading], scope: String,
                      climateRevision: String, failures: [String: String], checkedAt: Date,
                      thermostatSelectionRevision: String? = nil,
                      failureReasons: [String: HaReadingFailureReason] = [:]) throws -> HaStoreSnapshot? {
        guard let store = HaConfigStore.store else { throw HaError("Shared storage is unavailable") }
        return try store.merge(readings, expectedScope: scope, expectedClimateRevision: climateRevision,
            expectedThermostatSelectionRevision: thermostatSelectionRevision,
            failures: failures, failureReasons: failureReasons, checkedAt: checkedAt)
    }
}
