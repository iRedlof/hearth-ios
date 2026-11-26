import Foundation

public enum CarReadingsDestination: Sendable, Equatable {
    case ticket(UUID)
    case storageUnavailable
    case inert
}

public struct CarReadingsEntryPayload: Sendable, Equatable {
    public let entryID: UUID
    public let date: Date
    public let snapshot: CarSnapshot
    public let destination: CarReadingsDestination
    public let primary: CarReadingsPrimary
    public let readingsUnavailable: Bool
    public let smallReading: CarSmallReading?

    /// Allows preview and placeholder callers to create an inert payload without persistence.
    public init(entryID: UUID, date: Date, snapshot: CarSnapshot,
                destination: CarReadingsDestination, primary: CarReadingsPrimary = .noReading,
                readingsUnavailable: Bool? = nil, smallReading: CarSmallReading? = nil) {
        self.entryID = entryID
        self.date = date
        self.snapshot = snapshot
        self.destination = destination
        self.primary = primary
        self.readingsUnavailable = destination == .storageUnavailable || readingsUnavailable == true
        self.smallReading = smallReading
    }

    /// Preserve the chosen reading when an entry loses permission to publish executable controls.
    public func disablingInteractions() -> CarReadingsEntryPayload {
        CarReadingsEntryPayload(entryID: entryID, date: date, snapshot: snapshot,
            destination: .inert, primary: primary, readingsUnavailable: readingsUnavailable,
            smallReading: smallReading)
    }
}

/// Binds one completed envelope to one immutable opening record. The caller supplies persistence
/// and its issuance clock. Redelivery reuses the same envelope, IDs and date; a new entry uses new IDs.
/// Only successful persistence publishes a ticket destination; failures retain the chosen snapshot.
public func bindCarReadingsEntry(
    _ envelope: CarLiveEnvelope,
    entryID: UUID = UUID(),
    ticketID: UUID = UUID(),
    date: Date = .now,
    persist: (CarReadingsTicket) throws -> Void
) -> CarReadingsEntryPayload {
    let destination: CarReadingsDestination
    do {
        let ticket = try CarReadingsTicket(envelope: envelope, entryID: entryID,
            id: ticketID, issuedAt: date)
        try persist(ticket)
        destination = .ticket(ticket.id)
    } catch {
        destination = .storageUnavailable
    }
    let primary = carReadingsPrimary(origin: envelope.origin, cache: envelope.result.cache,
        error: envelope.result.error, setup: envelope.result.setup)
    return CarReadingsEntryPayload(entryID: entryID, date: date, snapshot: envelope.snapshot,
        destination: destination, primary: primary,
        smallReading: carSmallReading(result: envelope.result, primary: primary))
}
