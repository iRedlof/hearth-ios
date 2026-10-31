import Foundation
import XCTest
import HearthKit

final class CarReadingsRequestTests: XCTestCase {
    // Reusing the ticket UUID as the event UUID would let an older sheet callback own a new opening.
    func testOpeningTheSameTicketCreatesIndependentPresentationEvents() {
        let ticketID = UUID(uuidString: "12345678-1234-4234-8234-123456789ABC")!
        let first = CarReadingsRequest(destination: .ticket(ticketID))
        let second = CarReadingsRequest(destination: .ticket(ticketID))

        XCTAssertNotEqual(first.id, second.id)
        XCTAssertNotEqual(first.id, ticketID)
        XCTAssertNotEqual(second.id, ticketID)
        XCTAssertNotEqual(first, second)
    }

    // Replacing or normalizing the destination to a different ticket must not open another record.
    func testCompatibleIdentifierRetainsTheExactTicketDestination() {
        let request = CarReadingsRequest(identifier: "ABCDEF12-3456-4789-ABCD-123456789ABC")

        XCTAssertEqual(request.destination,
            .ticket(UUID(uuidString: "ABCDEF12-3456-4789-ABCD-123456789ABC")!))
        XCTAssertEqual(request.ticketID, UUID(uuidString: "ABCDEF12-3456-4789-ABCD-123456789ABC"))
    }

    // Invalid compatible intent input must never gain a saved-record or current-car destination.
    func testInvalidIdentifiersRemainNonoperatingRequests() {
        for identifier in ["", "unavailable", "current", "not-a-uuid", "hearth://car-readings/unavailable"] {
            let request = CarReadingsRequest(identifier: identifier)

            XCTAssertNil(request.destination, identifier)
            XCTAssertNil(request.ticketID, identifier)
        }
    }

    // Treating failed persistence like an inert preview would suppress its truthful explanation.
    func testUnavailableAndInertDestinationsRemainDistinctWithoutTickets() {
        let unavailable = CarReadingsRequest(destination: .storageUnavailable)
        let inert = CarReadingsRequest(destination: .inert)

        XCTAssertEqual(unavailable.destination, .storageUnavailable)
        XCTAssertEqual(inert.destination, .inert)
        XCTAssertNotEqual(unavailable.destination, inert.destination)
        XCTAssertNil(unavailable.ticketID)
        XCTAssertNil(inert.ticketID)
    }

    // Reopening must revoke the old callback identity while preserving the original saved record.
    func testReopeningRetainsTheRecordWithAFreshEvent() {
        let original = CarReadingsRequest(identifier: "12345678-1234-4234-8234-123456789ABC")
        let returned = original.reopened()

        XCTAssertEqual(returned.destination,
            .ticket(UUID(uuidString: "12345678-1234-4234-8234-123456789ABC")!))
        XCTAssertEqual(returned.ticketID, UUID(uuidString: "12345678-1234-4234-8234-123456789ABC"))
        XCTAssertNotEqual(returned.id, original.id)
        XCTAssertNotEqual(returned, original)
    }

    // A return helper must not promote unavailable, preview, or invalid requests to a current record.
    func testReopeningPreservesNonTicketDestinations() {
        let originals = [
            CarReadingsRequest(destination: .storageUnavailable),
            CarReadingsRequest(destination: .inert),
            CarReadingsRequest(identifier: "")
        ]

        for original in originals {
            let returned = original.reopened()
            XCTAssertEqual(returned.destination, original.destination)
            XCTAssertNil(returned.ticketID)
            XCTAssertNotEqual(returned.id, original.id)
        }
    }
}
