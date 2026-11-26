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

    /// Production widget entries retain the original envelope; only snapshot-only consumers
    /// above may display newer current-context readings after an obsolete completion.
    static func loadEntry(selection: CarReadingsEntrySelection,
                          allowsLivePublication: @escaping @Sendable () -> Bool = { true })
        async -> CarReadingsEntryPayload {
        await loadCarReadingsEntry(selection: selection,
            fetchEnvelope: { await fetchEnvelope() },
            persist: { ticket, issuedAt in
                // Open the App Group ticket store only when a live record is ready to save.
                guard let store = CarReadingsStore.store else { throw CocoaError(.fileNoSuchFile) }
                try store.save(ticket, now: issuedAt)
            }, allowsLivePublication: allowsLivePublication)
    }

    #if DEBUG
    /// The probe still binds one fetched envelope through the real entry loader and factory.
    /// Its captured dependencies never resolve a production store or a nil-request transport.
    static func loadEntry(selection: CarReadingsEntrySelection,
                          probe: CarRouteProbeDependencies,
                          didPersist: @escaping @Sendable (CarReadingsTicket) -> Void = { _ in },
                          allowsLivePublication: @escaping @Sendable () -> Bool = { true })
        async -> CarReadingsEntryPayload {
        await loadCarReadingsEntry(selection: selection,
            fetchEnvelope: probe.fetchEnvelope,
            persist: { ticket, issuedAt in
                // Recheck at the actual save boundary, including parity invalidation.
                guard probe.allowsPublication(), allowsLivePublication() else {
                    throw CarRouteProbeStorageError.invalid
                }
                try probe.persist(ticket, issuedAt)
                didPersist(ticket)
            },
            now: { probe.issuanceClock },
            allowsLivePublication: { probe.allowsPublication() && allowsLivePublication() })
    }
    #endif
}
