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
        XCTAssertEqual(lights.map(\.id), ["light.kitchen", "light.bed", "light.x"]) // unavailable retained, disabled
        XCTAssertFalse(lights[2].available)
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

    func testPinnedTilesReserveAWholeRowAndCountActualHiddenTiles() {
        func summary(main: Int, pins: Int) -> LightsSummary {
            let lights = (0..<(main + pins)).map {
                Light(id: "light.\($0)", name: "\($0)", on: true, percent: nil, since: nil)
            }
            return lightsSummary(lights, now: now, pinned: Set((main..<(main + pins)).map { "light.\($0)" }))
        }
        for pins in [3, 4, 5] {
            let page = lightTilePage(summary(main: 0, pins: pins))
            XCTAssertEqual(page.pinned.count, 2)
            XCTAssertEqual(page.hiddenCount, pins - 2)
        }
        let onePin = lightTilePage(summary(main: 3, pins: 1))
        XCTAssertEqual(onePin.main.count, 2)
        XCTAssertEqual(onePin.pinned.count, 1)
        XCTAssertEqual(onePin.hiddenCount, 1)
        let mixed = lightTilePage(summary(main: 1, pins: 3))
        XCTAssertEqual(mixed.hiddenCount, 1)
    }
}
