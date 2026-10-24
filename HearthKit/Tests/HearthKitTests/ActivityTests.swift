import XCTest
@testable import HearthKit

final class ActivityTests: XCTestCase {
    func testDedupesFiltersFormatsNewestFirst() {
        let log = """
        [
         {"when":"2026-10-24T07:00:00+00:00","entity_id":"alarm_control_panel.home","state":"armed_away"},
         {"when":"2026-10-24T07:05:00+00:00","entity_id":"lock.front","state":"locked"},
         {"when":"2026-10-24T07:05:30+00:00","entity_id":"lock.front","state":"locked"},
         {"when":"2026-10-24T07:06:00+00:00","entity_id":"alarm_control_panel.home","state":"arming"},
         {"when":"2026-10-24T07:10:00+00:00","entity_id":"cover.garage","state":"open","context_event_type":"automation_triggered","context_name":"[Ring][Away]: Routine"}
        ]
        """
        let names = ["alarm_control_panel.home": "Home Alarm", "lock.front": "Front Door", "cover.garage": "Garage"]
        let items = activityFrom(log, names: names, haStart: nil)
        // "arming" is an in-between step (dropped); the repeated lock is deduped; newest first.
        XCTAssertEqual(items.map(\.text), ["Garage opened", "Front Door locked", "Home Alarm armed away"])
        XCTAssertEqual(items.first?.kind, .garage)
        XCTAssertEqual(items.first?.by, "Ring Away routine")
    }

    func testUnknownEntitiesAndGarbageDropped() {
        let log = #"[{"when":"2026-10-24T07:00:00+00:00","entity_id":"lock.x","state":"locked"}]"#
        XCTAssertTrue(activityFrom(log, names: [:], haStart: nil).isEmpty)   // not in names → dropped
        XCTAssertTrue(activityFrom("not json", names: [:], haStart: nil).isEmpty)
    }
}
