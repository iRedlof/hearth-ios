import XCTest
@testable import HearthKit

final class CpLocationSearchTests: XCTestCase {
    func testBoundsCentredOnPoint() {
        let b = cpBounds(lat: 47.6, lon: -122.3, span: 0.02)
        XCTAssertEqual(b.swLat, 47.59, accuracy: 1e-9)
        XCTAssertEqual(b.neLat, 47.61, accuracy: 1e-9)
        XCTAssertEqual(b.swLon, -122.31, accuracy: 1e-9)
        XCTAssertEqual(b.neLon, -122.29, accuracy: 1e-9)
    }

    func testJoinBodyFromLocation() {
        let loc = CpLocation(name: "SEA41", address: "A", deviceIds: [1, 2, 3],
                             bounds: CpBounds(swLat: 1, swLon: 2, neLat: 3, neLon: 4))
        let body = cpJoinBody(loc)
        XCTAssertEqual(body["neLat"] as? Double, 3)
        XCTAssertEqual(body["swLon"] as? Double, 2)
        XCTAssertEqual(body["deviceIds"] as? [Int64], [1, 2, 3])
        XCTAssertNotNil(body["deviceData"])
    }

    func testLocationRoundTripsThroughJSON() throws {
        let loc = CpLocation(name: "SEA41", address: "400 Fairview", deviceIds: [9],
                             bounds: CpBounds(swLat: 1, swLon: 2, neLat: 3, neLon: 4), city: "Seattle", state: "WA", label: "Work")
        let data = try JSONEncoder().encode(loc)
        XCTAssertEqual(try JSONDecoder().decode(CpLocation.self, from: data), loc)
    }
}
