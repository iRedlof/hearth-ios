import XCTest
@testable import HearthKit

final class WidgetPreviewCatalogTests: XCTestCase {
    func testCompactWidgetsCannotAcquireAnUndesignedLargeFamily() {
        let compact: [WidgetPreviewKind] = [.alarm, .thermostat, .car, .chargepoint, .quick, .battery]
        for kind in compact {
            XCTAssertEqual(kind.supportedFamilies, [.medium], "\(kind) must remain medium only")
        }
    }

    func testCollectionsExposeOnlyTheirDesignedLargeFamily() {
        let collections: [WidgetPreviewKind] = [.doors, .activity, .lights, .favourites]
        for kind in collections {
            XCTAssertEqual(kind.supportedFamilies, [.large], "\(kind) must remain large only")
        }
    }

    func testCatalogCoversEveryShippedWidgetWithOneDesignedFamily() {
        let shipped: Set<WidgetPreviewKind> = [
            .alarm, .thermostat, .car, .chargepoint, .quick, .battery,
            .doors, .activity, .lights, .favourites
        ]
        XCTAssertEqual(Set(WidgetPreviewKind.allCases), shipped)
        for kind in WidgetPreviewKind.allCases {
            XCTAssertEqual(kind.supportedFamilies.count, 1, "\(kind) needs one designed preview family")
        }
    }
}
