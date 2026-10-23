import XCTest
@testable import HearthKit

final class CarFormattingTests: XCTestCase {
    let zone = TimeZone(identifier: "America/Los_Angeles")!
    let loc = Locale(identifier: "en_US")

    func testBeaconCarPair() {
        XCTAssertEqual(beaconCarPair(.calm,  charging: false, stale: false, hasReading: true).fillARGB,  0xFFB6D9C1) // mint
        XCTAssertEqual(beaconCarPair(.calm,  charging: true,  stale: false, hasReading: true).fillARGB,  0xFFA6D5FF) // blue
        XCTAssertEqual(beaconCarPair(.warn,  charging: true,  stale: false, hasReading: true).fillARGB,  0xFFF6D58A) // amber > charging
        XCTAssertEqual(beaconCarPair(.alert, charging: true,  stale: false, hasReading: true).fillARGB,  0xFFF2A0A4) // red
        XCTAssertEqual(beaconCarPair(.alert, charging: true,  stale: true,  hasReading: true).fillARGB,  0xFFBCC2B9) // grey (stale)
        XCTAssertEqual(beaconCarPair(.calm,  charging: false, stale: false, hasReading: false).fillARGB, 0xFFBCC2B9) // grey (no reading)
    }

    func testBeaconCarEta() {
        let now = parseOffsetDateTime("2026-10-20T17:00:00Z")!
        XCTAssertNil(beaconCarEta(now.addingTimeInterval(-1), now, zone, loc))
        XCTAssertNil(beaconCarEta(now, now, zone, loc))
        XCTAssertEqual(beaconCarEta(now.addingTimeInterval(3600), now, zone, loc), "Full by 11:00 AM")
        XCTAssertEqual(beaconCarEta(now.addingTimeInterval(90000), now, zone, loc), "Full by Wed 11:00 AM")
    }
}
