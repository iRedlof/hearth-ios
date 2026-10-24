import XCTest
@testable import HearthKit

final class BatteryTests: XCTestCase {
    func testParsesCleansAndClamps() {
        let json = """
        [{"id":"sensor.a_battery","name":"Living Area Motion Sensor Battery","level":55.4},
         {"id":"sensor.b","name":"Temperature Humidity Sensor: Master Bedroom Battery","level":8},
         {"id":"sensor.c","name":"","level":130}]
        """
        let b = batteriesFromTemplate(json)
        XCTAssertEqual(b.count, 3)
        XCTAssertEqual(b[0].name, "Living Area Motion Sensor")       // " Battery" stripped
        XCTAssertEqual(b[0].level, 55)                                // rounded
        XCTAssertEqual(b[1].name, "Master Bedroom sensor")            // "X: Y Battery" → "Y x"
        XCTAssertEqual(b[2].name, "sensor.c")                         // blank name → id
        XCTAssertEqual(b[2].level, 100)                               // clamped
    }

    func testGarbageYieldsNone() {
        XCTAssertEqual(batteriesFromTemplate("not json").count, 0)
        XCTAssertEqual(batteriesFromTemplate(nil).count, 0)
    }

    func testSummaryEmpty() {
        let s = batterySummary([])
        XCTAssertEqual(s.headline, "No batteries found")
        XCTAssertEqual(s.tone, .unknown)
    }

    func testSummaryAllGoodSortsLowestFirst() {
        let s = batterySummary([Battery(id: "a", name: "A", level: 90), Battery(id: "b", name: "B", level: 60)])
        XCTAssertEqual(s.headline, "All good")
        XCTAssertEqual(s.tone, .calm)
        XCTAssertEqual(s.rows.map(\.level), [60, 90])                 // lowest first
        XCTAssertEqual(s.detail, "Lowest: B 60%")
    }

    func testSummaryLowAndEmptyTone() {
        let warn = batterySummary([Battery(id: "a", name: "A", level: 25), Battery(id: "b", name: "B", level: 80)])
        XCTAssertEqual(warn.headline, "1 low")
        XCTAssertEqual(warn.tone, .warn)
        let alert = batterySummary([Battery(id: "a", name: "A", level: 8), Battery(id: "b", name: "B", level: 25)])
        XCTAssertEqual(alert.headline, "2 low")
        XCTAssertEqual(alert.tone, .alert)                            // one is <= EMPTY
    }
}
