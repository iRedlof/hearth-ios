import Foundation
import HearthKit

/// Snapshot and route attribution come from one owned, locked HA cache transaction.
enum CarLiveSnapshot {
    // Retire the legacy, separately persisted cache on account changes. It is never used as a
    // live origin: its check-and-set writes cannot establish cross-process ownership.
    private static let key = "carReadings"
    private static var defaults: UserDefaults { UserDefaults(suiteName: HaConfigStore.appGroup) ?? .standard }
    static func clear() { defaults.removeObject(forKey: key) }

    static func fetchEnvelope(now: Date = .now) async -> CarLiveEnvelope {
        guard let context = HaConfigStore.context(), let store = HaConfigStore.store else {
            return CarLiveEnvelope.storageUnavailable(now: now)
        }
        return await fetchOwnedCarEnvelope(store: store, context: context, now: now)
    }

    static func fetch(now: Date = .now) async -> CarSnapshot {
        let envelope = await fetchEnvelope(now: now)
        let current = envelope.origin.status == .obsolete ? HaConfigStore.context() : nil
        return envelope.presentationSnapshot(currentContext: current)
    }
}
