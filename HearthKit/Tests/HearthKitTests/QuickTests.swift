import XCTest
@testable import HearthKit

final class QuickTests: XCTestCase {
    func testScriptShortName() {
        XCTAssertEqual(scriptShortName("script.good_night"), "Good night")
        XCTAssertEqual(scriptShortName("script.all_off"), "All off")
        XCTAssertEqual(scriptShortName("movie"), "Movie")
    }
}
