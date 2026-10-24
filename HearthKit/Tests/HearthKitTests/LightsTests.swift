import XCTest
@testable import HearthKit

final class LightsTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    func testParseDropsGroupsSegmentsOffline() {
        let json = """
        [{"entity_id":"light.kitchen","state":"on","name":"Kitchen","brightness":204,"since":"2026-10-24T07:00:00+00:00","group":false,"rgb":[255,0,0]},
         {"entity_id":"light.all","state":"on","name":"All Lights","brightness":null,"since":"2026-10-24T07:00:00+00:00","group":true,"rgb":null},
         {"entity_id":"light.strip_segment_3","state":"on","name":"Strip Segment 3","brightness":null,"since":"2026-10-24T07:00:00+00:00","group":false,"rgb":null},
         {"entity_id":"light.bed","state":"off","name":"Bedroom","brightness":null,"since":"2026-10-24T07:00:00+00:00","group":false,"rgb":null},
         {"entity_id":"light.x","state":"unavailable","name":"X","brightness":null,"since":null,"group":false,"rgb":null}]
        """
        let lights = lightsFromTemplate(json)
        XCTAssertEqual(lights.map(\.id), ["light.kitchen", "light.bed"])   // group, segment, offline dropped
        XCTAssertEqual(lights[0].percent, 80)                              // 204/255 ≈ 80%
        XCTAssertEqual(lights[0].rgb, 0xFFFF0000)                          // red
        XCTAssertNil(lights[1].percent)                                    // off → no %
    }

    func testSummaryHeadlineAndSections() {
        let lights = [
            Light(id: "light.a", name: "Alpha", on: true, percent: 50, since: nil),
            Light(id: "light.b", name: "Bravo", on: false, percent: nil, since: nil),
            Light(id: "light.c", name: "Charlie", on: false, percent: nil, since: nil),
        ]
        let s = lightsSummary(lights, now: now, pinned: ["light.c"])
        XCTAssertEqual(s.headline, "Alpha on")       // exactly one on
        XCTAssertEqual(s.onCount, 1)
        XCTAssertEqual(s.on.map(\.id), ["light.a"])  // on, not pinned
        XCTAssertEqual(s.pinned.map(\.id), ["light.c"])
        XCTAssertEqual(s.offCount, 1)                // bravo off & unpinned (charlie pinned)
    }

    func testSummaryAllOffAndEmpty() {
        XCTAssertEqual(lightsSummary([], now: now).headline, "No lights found")
        XCTAssertEqual(lightsSummary([Light(id: "l.a", name: "A", on: false, percent: nil, since: nil)], now: now).headline, "All off")
    }
}
