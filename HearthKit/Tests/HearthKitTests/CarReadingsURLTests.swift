import Foundation
import XCTest
@testable import HearthKit

final class CarReadingsURLTests: XCTestCase {
    private let id = UUID(uuidString: "12345678-90AB-CDEF-1234-567890ABCDEF")!
    private let route = "hearth://car-readings/12345678-90AB-CDEF-1234-567890ABCDEF"

    // Changing the identifier, adding reading data, or changing the route breaks delivery.
    func testTicketURLContainsOnlyTheCanonicalOpaqueIdentifier() throws {
        let url = try XCTUnwrap(carReadingsURL(for: .ticket(id)))
        XCTAssertEqual(url.absoluteString, route)
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        XCTAssertEqual(components.scheme, "hearth")
        XCTAssertEqual(components.host, "car-readings")
        XCTAssertEqual(components.path, "/12345678-90AB-CDEF-1234-567890ABCDEF")
        XCTAssertNil(components.user)
        XCTAssertNil(components.password)
        XCTAssertNil(components.port)
        XCTAssertNil(components.query)
        XCTAssertNil(components.fragment)
        XCTAssertEqual(carReadingsDestination(from: url), .ticket(id))
    }

    // Treating persistence failure as an identifier must not publish an unrelated ticket.
    func testStorageUnavailableUsesOnlyTheReservedExplanationRoute() throws {
        let url = try XCTUnwrap(carReadingsURL(for: .storageUnavailable))
        XCTAssertEqual(url.absoluteString, "hearth://car-readings/unavailable")
        XCTAssertEqual(carReadingsDestination(from: url), .storageUnavailable)
    }

    // An inert preview or placeholder must not acquire a navigation target.
    func testInertHasNoURL() {
        XCTAssertNil(carReadingsURL(for: .inert))
    }

    // UUID casing cannot change which immutable ticket a tap opens.
    func testUUIDLetterCaseIsAcceptedWithoutChangingIdentity() throws {
        for value in [
            "hearth://car-readings/12345678-90AB-CDEF-1234-567890ABCDEF",
            "hearth://car-readings/12345678-90ab-cdef-1234-567890abcdef",
            "hearth://car-readings/12345678-90aB-cDeF-1234-567890AbCdEf"
        ] {
            XCTAssertEqual(carReadingsDestination(from: try XCTUnwrap(URL(string: value))),
                .ticket(id), value)
        }
    }

    // Dropping route identity checks would consume unrelated links, including OAuth callbacks.
    func testUnrelatedAndNoncanonicalSchemeOrHostAreIgnored() throws {
        for value in [
            "https://car-readings/12345678-90AB-CDEF-1234-567890ABCDEF",
            "HEARTH://car-readings/12345678-90AB-CDEF-1234-567890ABCDEF",
            "Hearth://car-readings/12345678-90AB-CDEF-1234-567890ABCDEF",
            "hearth://CAR-READINGS/12345678-90AB-CDEF-1234-567890ABCDEF",
            "hearth://Car-Readings/12345678-90AB-CDEF-1234-567890ABCDEF",
            "hearth://auth-callback?code=fixture-code&state=fixture-state",
            "hearth://other/12345678-90AB-CDEF-1234-567890ABCDEF",
            "hearth:/car-readings/12345678-90AB-CDEF-1234-567890ABCDEF",
            "hearth:///car-readings/12345678-90AB-CDEF-1234-567890ABCDEF",
            "//car-readings/12345678-90AB-CDEF-1234-567890ABCDEF"
        ] {
            XCTAssertNil(carReadingsDestination(from: try XCTUnwrap(URL(string: value))), value)
        }
    }

    // Accepting supplementary URL fields would expand the opaque route into a data channel.
    func testCredentialsPortsQueriesAndFragmentsAreRejectedEvenWhenEmpty() throws {
        for value in [
            "hearth://user@car-readings/12345678-90AB-CDEF-1234-567890ABCDEF",
            "hearth://user:password@car-readings/12345678-90AB-CDEF-1234-567890ABCDEF",
            "hearth://@car-readings/12345678-90AB-CDEF-1234-567890ABCDEF",
            "hearth://car-readings:443/12345678-90AB-CDEF-1234-567890ABCDEF",
            "hearth://car-readings:/12345678-90AB-CDEF-1234-567890ABCDEF",
            "hearth://car-readings/12345678-90AB-CDEF-1234-567890ABCDEF?",
            "hearth://car-readings/12345678-90AB-CDEF-1234-567890ABCDEF?account=fixture",
            "hearth://car-readings/12345678-90AB-CDEF-1234-567890ABCDEF#",
            "hearth://car-readings/12345678-90AB-CDEF-1234-567890ABCDEF#reading",
            "hearth://car-readings/unavailable?",
            "hearth://car-readings/unavailable#"
        ] {
            XCTAssertNil(carReadingsDestination(from: try XCTUnwrap(URL(string: value))), value)
        }
    }

    // Percent decoding or slash normalization must not admit alternate route spellings.
    func testEscapedAndExtraPathSegmentsAreRejected() throws {
        for value in [
            "hearth://car-readings/%312345678-90AB-CDEF-1234-567890ABCDEF",
            "hearth://car-readings/12345678%2D90AB-CDEF-1234-567890ABCDEF",
            "hearth://car-readings/%75navailable",
            "hearth://car-readings/unavailable%2F",
            "hearth://car-readings/%2F12345678-90AB-CDEF-1234-567890ABCDEF",
            "hearth://car-readings/%252F12345678-90AB-CDEF-1234-567890ABCDEF",
            "hearth://car-readings/12345678-90AB-CDEF-1234-567890ABCDEF/",
            "hearth://car-readings//12345678-90AB-CDEF-1234-567890ABCDEF",
            "hearth://car-readings/extra/12345678-90AB-CDEF-1234-567890ABCDEF",
            "hearth://car-readings/./12345678-90AB-CDEF-1234-567890ABCDEF",
            "hearth://car-readings/../12345678-90AB-CDEF-1234-567890ABCDEF",
            "hearth://car-readings/unavailable/"
        ] {
            XCTAssertNil(carReadingsDestination(from: try XCTUnwrap(URL(string: value))), value)
        }
    }

    // Missing IDs, arbitrary car selectors, and explanation aliases must fail closed.
    func testMissingUnknownAndMalformedIdentifiersAreRejected() throws {
        for value in [
            "hearth://car-readings",
            "hearth://car-readings/",
            "hearth://car-readings/current",
            "hearth://car-readings/latest",
            "hearth://car-readings/car-name",
            "hearth://car-readings/Unavailable",
            "hearth://car-readings/UNAVAILABLE",
            "hearth://car-readings/1234567890ABCDEF1234567890ABCDEF",
            "hearth://car-readings/12345678-90AB-CDEF-1234-567890ABCDE",
            "hearth://car-readings/12345678-90AB-CDEF-1234-567890ABCDEG"
        ] {
            XCTAssertNil(carReadingsDestination(from: try XCTUnwrap(URL(string: value))), value)
        }
    }
}
