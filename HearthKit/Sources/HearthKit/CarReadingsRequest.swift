import Foundation

/// One presentation event for an opaque saved record or a nonoperating explanation.
/// The event identity is independent of the ticket so repeated openings revoke older callbacks.
public struct CarReadingsRequest: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let destination: CarReadingsDestination?

    public var ticketID: UUID? {
        guard case .ticket(let id) = destination else { return nil }
        return id
    }

    /// Invalid legacy intent identifiers remain generic, nonoperating requests.
    public init(identifier: String) {
        self.init(retaining: UUID(uuidString: identifier).map(CarReadingsDestination.ticket))
    }

    public init(destination: CarReadingsDestination) {
        self.init(retaining: destination)
    }

    private init(retaining destination: CarReadingsDestination?) {
        id = UUID()
        self.destination = destination
    }

    /// Setup returns revalidate the same destination under a new presentation owner.
    public func reopened() -> Self { Self(retaining: destination) }
}
