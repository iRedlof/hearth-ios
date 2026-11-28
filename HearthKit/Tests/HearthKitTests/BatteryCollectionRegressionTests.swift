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
}
