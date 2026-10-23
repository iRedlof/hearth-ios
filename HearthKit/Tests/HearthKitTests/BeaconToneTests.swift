import XCTest
@testable import HearthKit

final class BeaconToneTests: XCTestCase {
    func testPaletteMatchesAndroid() {
        XCTAssertEqual(BeaconTone.mint.fillARGB, 0xFFB6D9C1)
        XCTAssertEqual(BeaconTone.mint.inkARGB, 0xFF244232)
        XCTAssertEqual(BeaconTone.blue.fillARGB, 0xFFA6D5FF)
        XCTAssertEqual(BeaconTone.red.inkARGB, 0xFF4D2029)
        XCTAssertEqual(BeaconTone.offline.fillARGB, 0xFFBCC2B9)
    }
}
