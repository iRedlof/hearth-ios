import XCTest
@testable import HearthKit

final class ActivitySnapshotTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_793_361_600)
    private let config = HaConfig(baseUrl: "https://home.example", token: "fixture", entityId: "alarm_control_panel.home", lockId: "lock.front")

    func testOldLastEventDoesNotClaimQuietThroughThePresent() {
        let event = ActivityItem(at: now.addingTimeInterval(-7500), kind: .lock, text: "Front Door locked", by: nil)
        let snapshot = ActivitySnapshot(items: [event], checkedAt: "10:00 AM",
                                        observedAt: now.addingTimeInterval(-7200))
        XCTAssertEqual(activitySnapshotHeadline(snapshot, now: now),
                       "Last event \(activityTimeLabel(event.at, now: now))")
    }

    func testSuccessfulCachedHistoryRetainsItsCheckTimeInFullAndCompactLayouts() {
        let event = ActivityItem(at: now.addingTimeInterval(-7500), kind: .lock, text: "Front Door locked", by: nil)
        for (width, height) in [(350.0, 366.0), (220.0, 110.0)] {
            for scale in [1.0, 1.6] {
                let layout = activityLayout(width: width, height: height, fontScale: scale,
                    items: [event], hasError: false, now: now, headline: "Last event 9:55 AM", checkedText: "Checked 10:00 AM")
                XCTAssertEqual(layout.checkedText, "Checked 10:00 AM")
                XCTAssertGreaterThan(layout.checkedLines, 0)
                XCTAssertLessThanOrEqual(layout.usedHeight, height)
            }
        }
    }

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
        XCTAssertEqual(activitySnapshotHeadline(failed, now: now), "History unavailable")
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

    func testWindowHeightScaleOverflowAndLegacyActionStayReadable() {
        let items = (0..<10).map { i in ActivityItem(at: now.addingTimeInterval(-Double(i)), kind: .lock,
            text: "An exceptionally long front entrance name locked", by: nil) }
        let compact = activityLayout(width: 360, height: 200, fontScale: 1, items: items, hasError: false)
        let tall = activityLayout(width: 360, height: 350, fontScale: 1, items: items, hasError: false)
        let large = activityLayout(width: 360, height: 200, fontScale: 1.6, items: items, hasError: false)
        XCTAssertEqual(compact.shown.count + compact.hiddenCount, 10)
        XCTAssertGreaterThan(tall.shown.count, compact.shown.count)
        XCTAssertLessThan(large.shown.count, compact.shown.count)
        XCTAssertEqual(activityDisplayParts(items[0]).action, "locked")
        XCTAssertEqual(activityDisplayParts(items[0]).name, "An exceptionally long front entrance name")
        XCTAssertEqual(activityInWindow([items[0], ActivityItem(at: now.addingTimeInterval(-86401), kind: .door, text: "Old opened", by: nil),
                                         ActivityItem(at: now.addingTimeInterval(1), kind: .door, text: "Future opened", by: nil)], now: now), [items[0]])
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

    func testScaledLongActionsMoveTimeBelowTheEvent() {
        let alarm = ActivityItem(at: now.addingTimeInterval(-60), kind: .alarm, text: "A long home alarm armed vacation",
                                 by: nil, name: "A long home alarm", action: "armed vacation")
        XCTAssertTrue(activityLayout(width: 360, height: 400, fontScale: 1.6, items: [alarm], hasError: false).narrow)
    }

    func testLegacyBypassAndTriggeredActionsRemainIndependentAndHaveRecentHeadlines() throws {
        let legacy = #"[{"at":815054340,"kind":"alarm","text":"A very long home alarm armed (bypass)","by":null}]"#
        let bypass = try JSONDecoder().decode([ActivityItem].self, from: Data(legacy.utf8))[0]
        let triggered = ActivityItem(at: now.addingTimeInterval(-60), kind: .alarm, text: "A very long home alarm alarm triggered", by: nil)
        XCTAssertEqual(activityDisplayParts(bypass).name, "A very long home alarm")
        XCTAssertEqual(activityDisplayParts(bypass).action, "armed (bypass)")
        XCTAssertEqual(activitySnapshotHeadline(ActivitySnapshot(items: [bypass], checkedAt: "Earlier"), now: now), "Armed (bypass)")
        XCTAssertEqual(activityDisplayParts(triggered).name, "A very long home alarm")
        XCTAssertEqual(activityDisplayParts(triggered).action, "alarm triggered")
    }

    func testMinimumHeightUsesBoundedExactCountSummaryIncludingFailedHistoryStamp() {
        let items = (0..<10).map { i in ActivityItem(at: now.addingTimeInterval(-Double(i)), kind: .lock,
            text: "A very long entrance name locked", by: nil) }
        for scale in [1.0, 1.6] {
            for failed in [false, true] {
                let plan = activityLayout(width: 220, height: 110, fontScale: scale, items: items, hasError: failed,
                    now: now, headline: failed ? "History unavailable" : "Locked", checkedText: failed ? "Last checked 9:41 AM" : nil)
                XCTAssertTrue(plan.summaryOnly)
                XCTAssertEqual(plan.hiddenCount, 10)
                XCTAssertEqual(plan.shown, [])
                XCTAssertEqual(plan.summaryLabel, failed ? "10 saved events" : "10 events")
                XCTAssertLessThanOrEqual(plan.usedHeight, 110)
                XCTAssertTrue(plan.showSummaryTitle)
                if failed { XCTAssertEqual(plan.checkedText, "Checked 9:41 AM") }
            }
        }
    }

    func testLargestTextAtModeBoundaryWrapsIndependentActionAndBudgetsExtraLine() {
        let alarm = ActivityItem(at: now.addingTimeInterval(-86400), kind: .alarm,
            text: "An exceptionally long home alarm alarm triggered", by: nil,
            name: "An exceptionally long home alarm", action: "alarm triggered")
        for width in [320.0, 328, 336] {
            let plan = activityLayout(width: width, height: 1000, fontScale: 3.2, items: [alarm], hasError: false,
                                      now: now, headline: "Alarm triggered")
            XCTAssertEqual(plan.rowMode, .stacked)
            XCTAssertEqual(plan.shown, [alarm])
            XCTAssertGreaterThanOrEqual(plan.rows[0].actionLines, 2)
            XCTAssertGreaterThanOrEqual(plan.rows[0].timeLines, 1)
            XCTAssertLessThanOrEqual(plan.usedHeight, 1000)
        }
    }

    func testPhysicallyShortLargestTextKeepsExactEventCountAtBodySize() {
        let item = ActivityItem(at: now.addingTimeInterval(-60), kind: .lock, text: "Front door locked", by: nil)
        let plan = activityLayout(width: 220, height: 110, fontScale: 3.2, items: Array(repeating: item, count: 10),
                                  hasError: false, now: now)
        XCTAssertTrue(plan.summaryOnly)
        XCTAssertEqual(plan.hiddenCount, 10)
        XCTAssertEqual(plan.summaryLabel, "10")
        XCTAssertLessThanOrEqual(plan.usedHeight, 110)
    }
}
