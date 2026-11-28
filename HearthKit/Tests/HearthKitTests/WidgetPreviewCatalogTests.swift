import XCTest
@testable import HearthKit

final class WidgetPreviewCatalogTests: XCTestCase {
    func testBeaconAndCompactWidgetsAreMediumOnly() {
        let medium: [WidgetPreviewKind] = [.car, .alarm, .thermostat, .chargepoint, .quick, .battery, .lights, .favourites]
        for kind in medium {
            XCTAssertEqual(kind.family, .medium, "\(kind) must remain medium only")
        }
    }

    func testCollectionsExposeOnlyTheirDesignedLargeFamily() {
        let collections: [WidgetPreviewKind] = [.activity]
        for kind in collections {
            XCTAssertEqual(kind.family, .large, "\(kind) must remain large only")
        }
    }

    func testNoWidgetHasASmallFamily() {
        XCTAssertEqual(WidgetPreviewFamily.allCases, [.medium, .large])
        XCTAssertEqual(WidgetPreviewFamily.allCases.map(\.title), ["Medium", "Large"])
    }

    func testCatalogCoversEveryShippedWidget() {
        let shipped: Set<WidgetPreviewKind> = [
            .alarm, .thermostat, .car, .chargepoint, .quick, .battery,
            .activity, .lights, .favourites
        ]
        XCTAssertEqual(Set(WidgetPreviewKind.allCases), shipped)
    }
}
