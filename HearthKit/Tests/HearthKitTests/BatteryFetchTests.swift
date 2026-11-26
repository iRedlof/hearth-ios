import XCTest
@testable import HearthKit

final class BatteryFetchTests: XCTestCase {
    private let connection = HaConfig(baseUrl: "https://example.com", token: "fixture", entityId: "")
    private let now = Date(timeIntervalSince1970: 1_793_399_400)

    func testMissingConnectionHasSetupStateWithoutSampleBatteries() async {
        let snapshot = await fetchBatterySnapshot(nil, now: now, read: {
            XCTFail("A disconnected fetch must not request batteries")
            return "[]"
        })
        XCTAssertEqual(snapshot.state, .setup)
        XCTAssertTrue(snapshot.summary.rows.isEmpty)
        XCTAssertTrue(snapshot.checkedAt.isEmpty)
        XCTAssertNil(snapshot.observedAt)
    }

    func testValidEmptyReadEarnsObservationWhileMalformedDoesNot() async {
        let empty = await fetchBatterySnapshot(connection, now: now, read: { "[]" })
        XCTAssertEqual(empty.state, .empty)
        XCTAssertEqual(empty.observedAt, now)
        XCTAssertFalse(empty.checkedAt.isEmpty)
        let malformed = await fetchBatterySnapshot(connection, now: now, read: { "{}" })
        XCTAssertEqual(malformed.state, .failed)
        XCTAssertNil(malformed.observedAt)
        XCTAssertTrue(malformed.checkedAt.isEmpty)
        XCTAssertNotNil(malformed.error)
    }

    func testFailureKeepsOwnedHistoricalRowsAndOriginalObservationTime() {
        let previous = mapBatterySnapshot(connection, reply: .success("""
        [{"id":"sensor.a","name":"Door Battery","level":80},
         {"id":"sensor.b","name":"Door Battery","level":20}]
        """), now: now)
        let failed = mapBatterySnapshot(connection, reply: .failure(HaError("Timed out")),
            previous: previous, now: now.addingTimeInterval(600))
        XCTAssertEqual(failed.state, .failed)
        XCTAssertEqual(failed.summary.rows.map(\.id), ["sensor.b", "sensor.a"])
        XCTAssertEqual(failed.summary, previous.summary)
        XCTAssertEqual(failed.observedAt, now)
        XCTAssertEqual(failed.checkedAt, previous.checkedAt)
        XCTAssertEqual(failed.error, "Timed out")
    }

    func testRepeatedFailureKeepsFirstObservationAndSuccessfulReadReplacesHistory() {
        let previous = mapBatterySnapshot(connection, reply: .success("[{\"id\":\"sensor.a\",\"level\":80}]"), now: now)
        let failed = mapBatterySnapshot(connection, reply: .failure(HaError("Timed out")), previous: previous,
                                       now: now.addingTimeInterval(600))
        let failedAgain = mapBatterySnapshot(connection, reply: .success("[null]"), previous: failed,
                                            now: now.addingTimeInterval(1200))
        XCTAssertEqual(failedAgain.observedAt, now)
        XCTAssertEqual(failedAgain.checkedAt, previous.checkedAt)
        let fresh = mapBatterySnapshot(connection, reply: .success("[]"), previous: failedAgain,
                                       now: now.addingTimeInterval(1800))
        XCTAssertEqual(fresh.state, .empty)
        XCTAssertEqual(fresh.observedAt, now.addingTimeInterval(1800))
        XCTAssertTrue(fresh.summary.rows.isEmpty)
        XCTAssertNil(fresh.error)
    }

    func testUnavailableCandidatesAreReadyButNeverAllGood() {
        let snapshot = mapBatterySnapshot(connection, reply: .success("""
        [{"id":"sensor.good","level":80},{"id":"sensor.unknown","state":"unknown","level":null}]
        """), now: now)
        XCTAssertEqual(snapshot.state, .ready)
        XCTAssertEqual(snapshot.summary.headline, "1 unavailable")
        XCTAssertEqual(snapshot.summary.tone, .unknown)
        XCTAssertEqual(Set(snapshot.summary.rows.map(\.id)), Set(["sensor.good", "sensor.unknown"]))
    }
}
