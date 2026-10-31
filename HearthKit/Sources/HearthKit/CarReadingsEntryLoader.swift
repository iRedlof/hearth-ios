import Foundation

public enum CarReadingsEntrySelection: Sendable {
    case live, inert
}

/// Inert samples never fetch or persist. Live entries bind exactly one completed envelope using
/// a single post-fetch issuance clock, shared by the ticket factory and persistence callback.
/// The optional publication guard lets a host invalidate live selection during suspension.
public func loadCarReadingsEntry(
    selection: CarReadingsEntrySelection,
    sample: CarSnapshot = .sample,
    fetchEnvelope: @Sendable () async -> CarLiveEnvelope,
    persist: @Sendable (CarReadingsTicket, Date) throws -> Void,
    now: @Sendable () -> Date = { .now },
    allowsLivePublication: @Sendable () -> Bool = { true }
) async -> CarReadingsEntryPayload {
    if selection == .inert {
        return CarReadingsEntryPayload(entryID: UUID(), date: now(), snapshot: sample,
            destination: .inert)
    }
    let envelope = await fetchEnvelope()
    let date = now()
    guard allowsLivePublication() else {
        return CarReadingsEntryPayload(entryID: UUID(), date: date, snapshot: sample,
            destination: .inert)
    }
    return bindCarReadingsEntry(envelope, date: date) { ticket in
        try persist(ticket, date)
    }
}
