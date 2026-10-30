import XCTest
@testable import HearthKit

final class BatteryCollectionRegressionTests: XCTestCase {
    func testOutOfRangeReadingsRemainWithoutInventedPercentages() {
        let batteries = batteriesFromTemplate("""
        [{"id":"sensor.high","name":"High","level":130},
         {"id":"sensor.negative","name":"Negative","level":-1}]
        """)
        XCTAssertEqual(batteries.count, 2)
        XCTAssertNil(batteries.first?.level)
        XCTAssertNil(batteries.last?.level)
    }

    func testUnknownReadingRemainsAndPreventsAllGood() {
        let batteries = batteriesFromTemplate("""
        [{"id":"sensor.good","name":"Door Battery","level":90},
         {"id":"sensor.missing","name":"Door Battery","level":"unavailable"}]
        """)
        XCTAssertEqual(batteries.map(\.id), ["sensor.good", "sensor.missing"])
        XCTAssertNotEqual(batterySummary(batteries).headline, "All good")
    }

    func testBinaryLowAndOKDoNotInventPercentageLevels() {
        let batteries = batteriesFromTemplate("""
        [{"id":"binary_sensor.low","name":"Low Battery","kind":"binary","state":"on"},
         {"id":"binary_sensor.ok","name":"OK Battery","kind":"binary","state":"off"}]
        """)
        XCTAssertEqual(batteries.count, 2)
        XCTAssertNil(batteries.first?.level)
        XCTAssertNil(batteries.last?.level)
        XCTAssertEqual(batterySummary(batteries).headline, "1 low")
    }

    func testBooleanIsUnavailableRatherThanOnePercent() {
        let batteries = batteriesFromTemplate("""
        [{"id":"sensor.bool","name":"Boolean","level":true}]
        """)
        XCTAssertEqual(batteries.count, 1)
        XCTAssertNil(batteries.first?.level)
    }

    func testDuplicateIdentifiersRejectResponseButDuplicateNamesSurvive() {
        XCTAssertTrue(batteriesFromTemplate("""
        [{"id":"sensor.a","level":10},{"id":"sensor.a","level":80}]
        """).isEmpty)
        let batteries = batteriesFromTemplate("""
        [{"id":"sensor.a","name":"Door Battery","level":10},
         {"id":"sensor.b","name":"Door Battery","level":80}]
        """)
        XCTAssertEqual(batteries.map(\.name), ["Door", "Door"])
    }

    func testHugeNonfiniteAndBooleanMeasurementsNeverCreateNumericReadings() throws {
        let values: [Any] = [Double.greatestFiniteMagnitude, Double.nan, Double.infinity, true, "Infinity", "NaN"]
        for value in values {
            XCTAssertNil(validatedBatteryPercent(value))
        }
        let batteries = try parseBatteryCollection("[{\"id\":\"sensor.huge\",\"level\":1e99}]")
        XCTAssertEqual(batteries.map(\.id), ["sensor.huge"])
        XCTAssertNil(batteries.first?.level)
    }

    func testRawThresholdsAreEvaluatedBeforeRoundingAndSurviveCache() throws {
        let batteries = try parseBatteryCollection("""
        [{"id":"sensor.healthy","level":30.4},{"id":"sensor.low","level":10.4}]
        """)
        let rows = batterySummary(batteriesFromJson(batteriesToJson(batteries))).rows
        XCTAssertEqual(rows.map(\.id), ["sensor.low", "sensor.healthy"])
        XCTAssertEqual(rows.map(\.low), [true, false])
        XCTAssertEqual(rows.map(\.empty), [false, false])
        XCTAssertEqual(rows.map(\.level), [10, 30])
        XCTAssertEqual(rows.map(\.rawLevel), [10.4, 30.4])
    }

    func testRawNumericOrderSurvivesEqualRoundedLevelsAndDuplicateFriendlyNames() throws {
        let rows = batterySummary(try parseBatteryCollection("""
        [{"id":"sensor.first","name":"Door","level":10.4},
         {"id":"sensor.second","name":"Door","level":10.1}]
        """)).rows
        XCTAssertEqual(rows.map(\.id), ["sensor.second", "sensor.first"])
    }

    func testCacheMissingLevelIsUnavailableAndBinaryRoundTripPreservesReading() throws {
        let missing = batteriesFromJson("[{\"id\":\"sensor.missing\",\"name\":\"Missing\"}]")
        XCTAssertEqual(missing.count, 1)
        XCTAssertNil(missing.first?.level)
        XCTAssertNotEqual(batterySummary(missing).headline, "1 low")
        let batteries = try parseBatteryCollection("""
        [{"id":"binary_sensor.low","state":"on"},{"id":"binary_sensor.ok","state":"off"},
         {"id":"binary_sensor.unknown","state":"unknown"}]
        """)
        let rows = batterySummary(batteriesFromJson(batteriesToJson(batteries))).rows
        XCTAssertEqual(rows.map(\.readingLabel), ["Low", "Unavailable", "OK"])
        XCTAssertEqual(rows.map(\.id), ["binary_sensor.low", "binary_sensor.unknown", "binary_sensor.ok"])
    }

    func testStrictEnvelopeDistinguishesEmptyFromMalformedAndRejectsMixedRows() throws {
        XCTAssertEqual(try parseBatteryCollection("[]"), [])
        for json in ["not json", "{}", "[null]", "[] trailing", "[{\"id\":\"sensor.good\",\"level\":80},7]"] {
            XCTAssertThrowsError(try parseBatteryCollection(json))
        }
    }

    func testOverflowCountsHiddenLowAndUnavailableReadings() throws {
        let rows = batterySummary(try parseBatteryCollection("""
        [{"id":"sensor.low","level":10},{"id":"binary_sensor.low","state":"on"},
         {"id":"sensor.missing","level":null},{"id":"sensor.good","level":90}]
        """)).rows
        XCTAssertEqual(batteryOverflow(rows), "4 more · 2 low · 1 unavailable")
    }

    func testHeightScaledFontAndErrorReserveReadableRows() {
        let medium = batteryRowBudget(height: 164, fontScale: 1, totalRows: 20, hasError: false, compact: true)
        let large = batteryRowBudget(height: 320, fontScale: 1, totalRows: 20, hasError: false)
        let scaled = batteryRowBudget(height: 300, fontScale: 2, totalRows: 20, hasError: false)
        let failed = batteryRowBudget(height: 300, fontScale: 2, totalRows: 20, hasError: true)
        XCTAssertEqual(medium.rows, 2)
        XCTAssertEqual(large.rows, 8)
        XCTAssertEqual(scaled.rows, 2)
        XCTAssertEqual(failed.rows, 1)
        XCTAssertTrue(failed.showError)
        XCTAssertTrue(failed.showOverflow)
        XCTAssertGreaterThan(scaled.readingWidth, large.readingWidth)
        XCTAssertEqual(batteryRowBudget(height: 80, fontScale: 2, totalRows: 20, hasError: true).rows, 0)
    }

    func testNarrowEnlargedOverflowKeepsEveryCountWithinLineCapacity() {
        for hasError in [false, true] {
            let budget = batteryCollectionBudget(width: 350, height: 164, fontScale: 2,
                rows: overflowFixture(), hasError: hasError, compact: true)
            XCTAssertTrue(budget.showOverflow)
            XCTAssertEqual(budget.overflowLines, ["20 more · 4 low", "4 unavailable"])
            XCTAssertTrue(budget.overflowLines.allSatisfy { batteryOverflowLineWidth($0, fontScale: 2) <= 338 })
            XCTAssertLessThanOrEqual(budget.contentHeight, 164)
            XCTAssertEqual(budget.rows, 0)
        }
    }

    func testMinimumSizeKeepsEveryCountWithoutShrinkingText() {
        for hasError in [false, true] {
            let budget = batteryCollectionBudget(width: 220, height: 110, fontScale: 2,
                rows: overflowFixture(), hasError: hasError, compact: true)
            XCTAssertEqual(budget.overflowLines, hasError ? ["20 saved", "4 low 4 N/A"] : ["20 more 4 low", "4 N/A"])
            XCTAssertTrue(budget.overflowLines.allSatisfy { batteryOverflowLineWidth($0, fontScale: 2) <= 208 })
            XCTAssertEqual(budget.overflowLineHeight, 32)
            XCTAssertLessThanOrEqual(budget.contentHeight, 110)
            XCTAssertEqual(budget.headerMode, .none)
        }
    }

    func testWiderOverflowPermitsMoreRowsAndRetainsEveryHiddenStatusCount() {
        let rows = overflowFixture()
        let narrow = batteryCollectionBudget(width: 280, height: 320, fontScale: 2, rows: rows, hasError: true)
        let wide = batteryCollectionBudget(width: 700, height: 320, fontScale: 2, rows: rows, hasError: true)
        XCTAssertGreaterThan(wide.rows, narrow.rows)
        let hidden = rows.dropFirst(narrow.rows)
        let text = narrow.overflowLines.joined(separator: " ")
        XCTAssertTrue(text.contains("\(hidden.filter(\.low).count) low"))
        XCTAssertTrue(text.contains("\(hidden.filter { !$0.available }.count) unavailable"))
        XCTAssertLessThanOrEqual(narrow.contentHeight, 320)
    }

    func testLargestAccessibilityScaleRetainsEveryMediumWidgetCount() {
        let budget = batteryCollectionBudget(width: 350, height: 164, fontScale: 3.4,
            rows: overflowFixture(), hasError: true, compact: true)
        XCTAssertTrue(budget.showOverflow)
        let text = budget.overflowLines.joined(separator: " ")
        XCTAssertTrue(text.contains("20"))
        XCTAssertTrue(text.contains("4 low"))
        XCTAssertTrue(text.contains("4 N/A"))
        XCTAssertTrue(budget.overflowLines.allSatisfy { batteryOverflowLineWidth($0, fontScale: 3.4) <= 338 })
        XCTAssertLessThanOrEqual(budget.contentHeight, 164)
    }

    private func overflowFixture() -> [BatteryRow] {
        batterySummary(
            (1...4).map { Battery(id: "sensor.low\($0)", name: "Low \($0)", level: 20) } +
                (1...4).map { Battery(id: "sensor.missing\($0)", name: "Missing \($0)", level: nil) } +
                (1...12).map { Battery(id: "sensor.good\($0)", name: "Good \($0)", level: 90) }
        ).rows
    }
}
