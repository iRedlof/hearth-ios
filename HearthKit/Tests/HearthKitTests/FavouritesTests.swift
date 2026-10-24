import XCTest
@testable import HearthKit

final class FavouritesTests: XCTestCase {
    func testFavServiceForFlipsOrRuns() {
        XCTAssertEqual(favServiceFor("script.x", on: false).domain, "script")
        XCTAssertEqual(favServiceFor("script.x", on: false).service, "turn_on")  // scripts always run
        XCTAssertEqual(favServiceFor("script.x", on: true).service, "turn_on")
        XCTAssertEqual(favServiceFor("switch.x", on: true).service, "turn_off")  // flip off
        XCTAssertEqual(favServiceFor("light.x", on: false).service, "turn_on")   // flip on
        XCTAssertEqual(favServiceFor("fan.x", on: true).domain, "fan")
        XCTAssertEqual(favServiceFor("input_boolean.x", on: false).service, "turn_on")
    }

    func testDomain() {
        XCTAssertEqual(Fav(id: "switch.coffee", name: "C", on: true).domain, "switch")
    }
}
