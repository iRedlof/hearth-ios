import XCTest
@testable import HearthKit

final class ActivitySnapshotTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_793_361_600)
    private let config = HaConfig(baseUrl: "https://home.example", token: "fixture", entityId: "alarm_control_panel.home", lockId: "lock.front")

    func testValidEmptyLogbookIsDistinctFromMalformedResponse() {
        let empty = mapActivitySnapshot(config: config, reply: .success("[]"), names: ["lock.front": "Front Door"], now: now)
        XCTAssertEqual(empty.state, .empty)
        XCTAssertEqual(empty.observedAt, now)
        XCTAssertFalse(empty.checkedAt.isEmpty)
        for malformed in ["{}", "null", "[1]", "not json"] {
            let failed = mapActivitySnapshot(config: config, reply: .success(malformed), names: ["lock.front": "Front Door"], now: now)
            XCTAssertEqual(failed.state, .failed, malformed)
            XCTAssertNil(failed.observedAt)
            XCTAssertEqual(failed.checkedAt, "")
        }
    }

    func testFailedHistoricalSnapshotPreservesOriginalObservationAndWindow() {
        let observed = now.addingTimeInterval(-3600)
        let item = ActivityItem(at: now.addingTimeInterval(-7200), kind: .lock, text: "Front Door locked", by: nil)
        let previous = ActivitySnapshot(items: [item], checkedAt: "Earlier", observedAt: observed, windowEnd: observed)
        let failed = mapActivitySnapshot(config: config, reply: .failure(HaError("Offline")), names: ["lock.front": "Front Door"],
                                         previous: previous, now: now)
        XCTAssertEqual(failed.state, .failed)
        XCTAssertEqual(failed.items, [item])
        XCTAssertEqual(failed.checkedAt, "Earlier")
        XCTAssertEqual(failed.observedAt, observed)
        XCTAssertEqual(failed.windowEnd, observed)
    }

    func testSelectedMissingNameFallsBackAndUnrequestedEntityIsExcluded() {
        let log = """
        [
         {"when":"2026-10-30T11:59:00Z","entity_id":"lock.front","state":"locked"},
         {"when":"2026-10-30T11:59:30Z","entity_id":"lock.unrequested","state":"unlocked","name":"Side Door"},
         {"when":"2026-10-30T11:59:40Z","entity_id":"switch.porch","state":"on","name":"Porch"}
        ]
        """
        let captured = Date(timeIntervalSince1970: 1_793_361_600) // 2026-10-30 12:00 UTC
        let snapshot = mapActivitySnapshot(config: config, reply: .success(log), names: [:], now: captured)
        XCTAssertEqual(snapshot.items.map(\.text), ["Front door locked"])
    }

    func testInjectedReadFailureReturnsFailureWithoutFreshStamp() async {
        let snapshot = await fetchActivitySnapshot(config, now: now, read: { throw HaError("Offline") })
        XCTAssertEqual(snapshot.state, .failed)
        XCTAssertEqual(snapshot.checkedAt, "")
        XCTAssertNil(snapshot.observedAt)
    }

    func testLegacyActionSplitsFromALongNameAndTheWindowIsTheLastDay() {
        let item = ActivityItem(at: now, kind: .lock, text: "An exceptionally long front entrance name locked", by: nil)
        XCTAssertEqual(activityDisplayParts(item).action, "locked")
        XCTAssertEqual(activityDisplayParts(item).name, "An exceptionally long front entrance name")
        XCTAssertEqual(activityInWindow([item, ActivityItem(at: now.addingTimeInterval(-86401), kind: .door, text: "Old opened", by: nil),
                                         ActivityItem(at: now.addingTimeInterval(1), kind: .door, text: "Future opened", by: nil)], now: now), [item])
    }

    func testDateLabelsDistinguishYesterdayFromOlderAndFutureDates() {
        let captured = Date(timeIntervalSince1970: 1_793_361_600)
        let zone = TimeZone(secondsFromGMT: 0)!
        let locale = Locale(identifier: "en_US")
        XCTAssertEqual(activityTimeLabel(captured.addingTimeInterval(-3600), now: captured, zone: zone, locale: locale), "11:00 AM")
        XCTAssertEqual(activityTimeLabel(captured.addingTimeInterval(-90000), now: captured, zone: zone, locale: locale), "Yest 11:00 AM")
        XCTAssertEqual(activityTimeLabel(captured.addingTimeInterval(-176400), now: captured, zone: zone, locale: locale), "Oct 28 11:00 AM")
        XCTAssertEqual(activityTimeLabel(captured.addingTimeInterval(82800), now: captured, zone: zone, locale: locale), "Oct 31 11:00 AM")
    }

    func testLegacyBypassAndTriggeredActionsRemainIndependent() throws {
        let legacy = #"[{"at":815054340,"kind":"alarm","text":"A very long home alarm armed (bypass)","by":null}]"#
        let bypass = try JSONDecoder().decode([ActivityItem].self, from: Data(legacy.utf8))[0]
        let triggered = ActivityItem(at: now.addingTimeInterval(-60), kind: .alarm, text: "A very long home alarm alarm triggered", by: nil)
        XCTAssertEqual(activityDisplayParts(bypass).name, "A very long home alarm")
        XCTAssertEqual(activityDisplayParts(bypass).action, "armed (bypass)")
        XCTAssertEqual(activityDisplayParts(triggered).name, "A very long home alarm")
        XCTAssertEqual(activityDisplayParts(triggered).action, "alarm triggered")
    }
}
