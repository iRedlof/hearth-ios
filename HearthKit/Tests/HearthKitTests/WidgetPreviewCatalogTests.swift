import XCTest
@testable import HearthKit

final class WidgetPreviewCatalogTests: XCTestCase {
    func testEveryWidgetIsMediumOnly() {
        for kind in WidgetPreviewKind.allCases {
            XCTAssertEqual(kind.family, .medium, "\(kind) must remain medium only")
        }
    }

    func testMediumIsTheOnlyFamily() {
        XCTAssertEqual(WidgetPreviewFamily.allCases, [.medium])
        XCTAssertEqual(WidgetPreviewFamily.allCases.map(\.title), ["Medium"])
        XCTAssertNil(WidgetPreviewFamily(rawValue: "small"))
        XCTAssertNil(WidgetPreviewFamily(rawValue: "large"))
    }

    func testCatalogCoversEveryShippedWidget() {
        let shipped: Set<WidgetPreviewKind> = [
            .alarm, .thermostat, .car, .chargepoint, .quick, .battery,
            .activity, .lights, .favourites
        ]
        XCTAssertEqual(Set(WidgetPreviewKind.allCases), shipped)
    }
}
