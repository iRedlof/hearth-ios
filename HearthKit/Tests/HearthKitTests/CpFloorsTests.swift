import XCTest
@testable import HearthKit

/// Floor-level availability grouping for the ChargePoint card (ported from Android CpRight.Floors).
final class CpFloorsTests: XCTestCase {
    private func station(_ id: Int64, _ level: String, free: Int, inUse: Int, offline: Int) -> CpStation {
        CpStation(deviceId: id, address: "", name: "", lat: 0, lon: 0, site: "SEA41",
                  free: free, inUse: inUse, offline: offline, waitlist: true, city: "", state: "", level: level)
    }
    private let loc = CpLocation(name: "SEA41", address: "", deviceIds: [1, 2, 3],
                                 bounds: CpBounds(swLat: 0, swLon: 0, neLat: 0, neLon: 0))

    func testFloorsGroupByLevelSortedWithFreeAndTotal() {
        let stations = [
            station(1, "P3", free: 2, inUse: 1, offline: 0),
            station(2, "P3", free: 1, inUse: 0, offline: 1),
            station(3, "P2", free: 0, inUse: 3, offline: 0),
        ]
        let floors = cpFloorsFrom(loc, stations)
        XCTAssertEqual(floors.map(\.level), ["P2", "P3"])   // level-sorted (P2 before P3)
        XCTAssertEqual(floors[0].free, 0); XCTAssertEqual(floors[0].total, 3)
        XCTAssertEqual(floors[1].free, 3); XCTAssertEqual(floors[1].total, 5)   // (2+1+0)+(1+0+1)
    }

    func testStationsOutsideLocationIgnoredAndNoLevelDropped() {
        let stations = [
            station(1, "P2", free: 1, inUse: 0, offline: 0),
            station(9, "P5", free: 9, inUse: 0, offline: 0),   // deviceId not in the location
            station(2, "", free: 4, inUse: 0, offline: 0),      // no level → dropped
        ]
        let floors = cpFloorsFrom(loc, stations)
        XCTAssertEqual(floors.map(\.level), ["P2"])
        XCTAssertEqual(floors[0].free, 1)
    }
}
