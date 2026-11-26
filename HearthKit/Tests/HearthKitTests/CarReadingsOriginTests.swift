import XCTest
@testable import HearthKit

final class CarReadingsOriginTests: XCTestCase {
    private let observed = Date(timeIntervalSince1970: 1_800_000_000)

    private static func reply(battery: String, prefixJSON: String) -> String {
        """
        {"found":true,"prefix":\(prefixJSON),"name":"Same display name","unit":"mi","s":{
        "sensor.battery_level":"\(battery)","sensor.charging":"charging",
        "sensor.charger_power":"7.25","lock.lock":"locked"}}
        """
    }

    // A padded prefix still identifies the same vehicle, rather than losing its real history.
    func testHistoryUsesNormalizedCurrentVehiclePrefix() throws {
        let good = try carReadingsAfterReply(
            Self.reply(battery: "84", prefixJSON: #"" stargate \n""#),
            previous: nil, checkedAt: observed)
        let unknown = try carReadingsAfterReply(
            Self.reply(battery: "unknown", prefixJSON: #""stargate""#),
            previous: good, checkedAt: observed.addingTimeInterval(60))
        XCTAssertEqual(CarFetchResult(cache: unknown).snapshot(now: observed).battery, 84)
        XCTAssertTrue(CarFetchResult(cache: unknown).snapshot(now: observed).stale)
    }

    // Equal blank prefixes never authorize cross-reading history attribution.
    func testWhitespaceOnlyPrefixCannotRetainHistory() throws {
        let good = try carReadingsAfterReply(
            Self.reply(battery: "84", prefixJSON: #"" \n ""#),
            previous: nil, checkedAt: observed)
        let unknown = try carReadingsAfterReply(
            Self.reply(battery: "unknown", prefixJSON: #"" \n ""#),
            previous: good, checkedAt: observed.addingTimeInterval(60))
        XCTAssertNil(CarFetchResult(cache: unknown).snapshot(now: observed).battery)
        XCTAssertNil(unknown.lastGood)
    }

    // A non-string prefix leaves readable telemetry unidentified, rather than borrowing history.
    func testNonStringPrefixRemainsUnidentifiedWithoutRejectingTelemetry() throws {
        let value = try carReadingsAfterReply(
            Self.reply(battery: "73", prefixJSON: "123"),
            previous: nil, checkedAt: observed)
        XCTAssertEqual(CarFetchResult(cache: value).snapshot(now: observed).battery, 73)
    }

    // A cache cannot make historical telemetry from another car look like this car's readings.
    func testSnapshotRejectsUnattributedHistoricalCache() {
        let cache = CarReadingsCache(
            current: Self.reply(battery: "unknown", prefixJSON: #""new-car""#),
            lastGood: Self.reply(battery: "84", prefixJSON: #""old-car""#), checkedAt: observed)
        XCTAssertNil(CarFetchResult(cache: cache).snapshot(now: observed).battery)
        XCTAssertFalse(CarFetchResult(cache: cache).snapshot(now: observed).stale)
    }

    // The timeline's check time must not erase when retained telemetry was actually observed.
    func testRetainedTelemetryPersistsItsActualObservationTime() throws {
        struct HistoryTime: Decodable { let lastGoodCheckedAt: Date? }
        let good = try carReadingsAfterReply(
            Self.reply(battery: "84", prefixJSON: #""stargate""#),
            previous: nil, checkedAt: observed)
        let unknown = try carReadingsAfterReply(
            Self.reply(battery: "unknown", prefixJSON: #""stargate""#),
            previous: good, checkedAt: observed.addingTimeInterval(60))
        let time = try JSONDecoder().decode(HistoryTime.self, from: JSONEncoder().encode(unknown))
        XCTAssertEqual(time.lastGoodCheckedAt, observed)
        XCTAssertEqual(unknown.checkedAt, observed.addingTimeInterval(60))
    }

    // A legacy cache without the old telemetry time must leave that time unknown, rather than restamping it.
    func testLegacyHistoryDoesNotInventObservationTime() throws {
        let legacy = CarReadingsCache(
            current: Self.reply(battery: "unknown", prefixJSON: #""stargate""#),
            lastGood: Self.reply(battery: "84", prefixJSON: #""stargate""#), checkedAt: observed)
        let next = try carReadingsAfterReply(
            Self.reply(battery: "unknown", prefixJSON: #""stargate""#),
            previous: legacy, checkedAt: observed.addingTimeInterval(60))
        let result = CarFetchResult(cache: next)
        XCTAssertEqual(result.shownCar?.car.battery, 84)
        XCTAssertTrue(result.shownCar?.stale == true)
        XCTAssertNil(result.displayedObservedAt)
        XCTAssertNil(next.lastGoodCheckedAt)
        XCTAssertEqual(next.checkedAt, observed.addingTimeInterval(60))
    }
}
