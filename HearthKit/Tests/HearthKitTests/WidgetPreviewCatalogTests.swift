import XCTest
@testable import HearthKit

final class WidgetPreviewCatalogTests: XCTestCase {
    func testCompactWidgetsCannotAcquireAnUndesignedLargeFamily() {
        let compact: [WidgetPreviewKind] = [.alarm, .chargepoint, .quick, .battery]
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

    func testDesignedSmallFamiliesPreserveMediumDefaults() {
        XCTAssertEqual(WidgetPreviewKind.thermostat.family, .medium)
        XCTAssertEqual(WidgetPreviewKind.thermostat.supportedFamilies, [.small, .medium])
        XCTAssertEqual(WidgetPreviewFamily.small.title, "Small")
        XCTAssertEqual(WidgetPreviewKind.car.family, .medium)
        XCTAssertEqual(WidgetPreviewKind.car.supportedFamilies, [.small, .medium])
        for kind in WidgetPreviewKind.allCases where kind != .thermostat && kind != .car {
            XCTAssertFalse(kind.supportedFamilies.contains(.small), "\(kind) has no Small design")
        }
    }

    func testCatalogCoversEveryShippedWidgetWithItsDesignedFamilies() {
        let shipped: Set<WidgetPreviewKind> = [
            .alarm, .thermostat, .car, .chargepoint, .quick, .battery,
            .doors, .activity, .lights, .favourites
        ]
        XCTAssertEqual(Set(WidgetPreviewKind.allCases), shipped)
        for kind in WidgetPreviewKind.allCases {
            XCTAssertEqual(kind.supportedFamilies.count, [.thermostat, .car].contains(kind) ? 2 : 1)
        }
    }
}
