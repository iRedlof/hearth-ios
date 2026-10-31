import Foundation

/// Screen lifetime is independent from account identity and the immutable widget opening record.
public struct CarReadingsRouteSession: Sendable {
    public private(set) var shownTicket: CarReadingsTicket
    public private(set) var status: CarReadingsRouteStatus
    public private(set) var refreshing = false
    private var active = true
    private var refreshClaim: UUID?

    public init(ticket: CarReadingsTicket, context: HaStoreSnapshot?, now: Date = .now) {
        shownTicket = ticket
        status = ticket.validation(in: context, now: now)
    }

    public mutating func revalidate(context: HaStoreSnapshot?, now: Date = .now) {
        status = shownTicket.validation(in: context, now: now)
    }
    public mutating func beginRefresh(context: HaStoreSnapshot?, now: Date = .now) -> UUID? {
        guard active, !refreshing else { return nil }
        revalidate(context: context, now: now)
        guard status == .current else { return nil }
        let claim = UUID()
        refreshClaim = claim
        refreshing = true
        return claim
    }
    public mutating func finishRefresh(claim: UUID, ticket: CarReadingsTicket?,
                                       context: HaStoreSnapshot?, now: Date = .now) -> Bool {
        guard active, refreshing, refreshClaim == claim else { return false }
        refreshing = false
        refreshClaim = nil
        revalidate(context: context, now: now)
        guard status == .current, let ticket else { return false }
        guard ticket.origin.requestScope == shownTicket.origin.requestScope,
              ticket.origin.vehiclePrefix == shownTicket.origin.vehiclePrefix,
              ticket.validation(in: context, now: now) == .current else { return false }
        shownTicket = ticket
        return true
    }
    public mutating func close() {
        active = false
        refreshing = false
        refreshClaim = nil
    }
}
