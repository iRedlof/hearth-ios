import XCTest
@testable import HearthKit

final class ActivityTests: XCTestCase {
    func testInvalidTimestampCannotSuppressTheNextValidState() {
        let log = """
        [
         {"when":"not a timestamp","entity_id":"lock.front","state":"locked"},
         {"when":"2026-10-24T07:00:00Z","entity_id":"lock.front","state":"locked"}
        ]
        """
        XCTAssertEqual(activityFrom(log, names: ["lock.front": "Front Door"], haStart: nil).map(\.text),
                       ["Front Door locked"])
    }

    func testUnavailableBetweenEqualFinalStatesDoesNotCreateASecondEvent() {
        let log = """
        [
         {"when":"2026-10-24T07:00:00Z","entity_id":"binary_sensor.back","state":"off"},
         {"when":"2026-10-24T07:01:00Z","entity_id":"binary_sensor.back","state":"unavailable"},
         {"when":"2026-10-24T07:02:00Z","entity_id":"binary_sensor.back","state":"off"}
        ]
        """
        XCTAssertEqual(activityFrom(log, names: ["binary_sensor.back": "Back Door"], haStart: nil).map(\.text),
                       ["Back Door closed"])
    }

    func testLockingBetweenEqualLockedStatesDoesNotCreateASecondEvent() {
        let log = """
        [
         {"when":"2026-10-24T07:00:00Z","entity_id":"lock.front","state":"locked"},
         {"when":"2026-10-24T07:01:00Z","entity_id":"lock.front","state":"locking"},
         {"when":"2026-10-24T07:02:00Z","entity_id":"lock.front","state":"locked"}
        ]
        """
        XCTAssertEqual(activityFrom(log, names: ["lock.front": "Front Door"], haStart: nil).map(\.text),
                       ["Front Door locked"])
    }

    func testUnrelatedGarageSideDoorIsPreservedBesideTheOpener() {
        let log = """
        [
         {"when":"2026-10-24T07:00:00Z","entity_id":"cover.garage","state":"open"},
         {"when":"2026-10-24T07:00:10Z","entity_id":"binary_sensor.garage_side","state":"on"}
        ]
        """
        XCTAssertEqual(activityFrom(log, names: ["cover.garage": "Garage", "binary_sensor.garage_side": "Garage Side Door"],
                                    haStart: nil).map(\.text), ["Garage Side Door opened", "Garage opened"])
    }

    func testUnsupportedSwitchIsNotInterpretedAsADoorOpening() {
        let log = #"[{"when":"2026-10-24T07:00:00Z","entity_id":"switch.porch","state":"on"}]"#
        XCTAssertTrue(activityFrom(log, names: ["switch.porch": "Porch"], haStart: nil).isEmpty)
    }

    func testUnconfiguredFetchHasNoSampleEventsOrCheckedStamp() async {
        let config = HaConfig(baseUrl: "", token: "", entityId: "")
        let snapshot = await fetchActivitySnapshot(config, now: Date(timeIntervalSince1970: 1_798_000_000))
        XCTAssertTrue(snapshot.items.isEmpty)
        XCTAssertEqual(snapshot.checkedAt, "")
    }

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

    func testExplicitGaragePairSuppressesOnlyItsOwnEcho() {
        let log = """
        [
         {"when":"2026-10-24T07:00:00Z","entity_id":"cover.garage","state":"open"},
         {"when":"2026-10-24T07:00:10Z","entity_id":"binary_sensor.garage","state":"on"},
         {"when":"2026-10-24T07:00:20Z","entity_id":"binary_sensor.garage_side","state":"on"}
        ]
        """
        let names = ["cover.garage": "Garage", "binary_sensor.garage": "Garage Door", "binary_sensor.garage_side": "Garage Side Door"]
        XCTAssertEqual(activityFrom(log, names: names, haStart: nil,
                                    pairedSensors: ["binary_sensor.garage": "cover.garage"]).map(\.text),
                       ["Garage Side Door opened", "Garage opened"])
    }

    func testCacheRoundTripPreservesEntityActionAndIdentity() throws {
        let log = #"[{"when":"2026-10-24T07:00:00Z","entity_id":"lock.front","state":"locked"}]"#
        let items = activityFrom(log, names: ["lock.front": "Front Door"], haStart: nil)
        let restored = try JSONDecoder().decode([ActivityItem].self, from: JSONEncoder().encode(items))
        XCTAssertEqual(restored.first?.entityId, "lock.front")
        XCTAssertEqual(restored.first?.name, "Front Door")
        XCTAssertEqual(restored.first?.action, "locked")
        XCTAssertEqual(restored.first?.eventKey, items.first?.eventKey)
    }

    func testLegacyCacheDecodesAndSeparatesActionFromLongName() throws {
        let json = #"[{"at":0,"kind":"lock","text":"An exceptionally long front entrance name locked","by":null}]"#
        let items = try JSONDecoder().decode([ActivityItem].self, from: Data(json.utf8))
        XCTAssertEqual(activityDisplayParts(items[0]).name, "An exceptionally long front entrance name")
        XCTAssertEqual(activityDisplayParts(items[0]).action, "locked")
        XCTAssertEqual(items[0].entityId, "")
    }

    func testFiveMinuteRestartGraceDoesNotDuplicateOrRetimestampEvents() {
        let start = Date(timeIntervalSince1970: 1_798_800_000)
        XCTAssertNil(trustedSince(start.addingTimeInterval(299), start))
        XCTAssertEqual(trustedSince(start.addingTimeInterval(300), start), start.addingTimeInterval(300))
        XCTAssertEqual(trustedSince(start.addingTimeInterval(60), nil), start.addingTimeInterval(60))
    }

    func testEqualTimestampsHaveStableEntityOrdering() {
        let log = """
        [
         {"when":"2026-10-24T07:00:00Z","entity_id":"lock.front","state":"locked"},
         {"when":"2026-10-24T07:00:00Z","entity_id":"alarm_control_panel.home","state":"disarmed"}
        ]
        """
        XCTAssertEqual(activityFrom(log, names: ["lock.front": "Front Door", "alarm_control_panel.home": "Alarm"],
                                    haStart: nil).map(\.text), ["Alarm disarmed", "Front Door locked"])
    }

    func testOldStateOutsideWindowCannotSuppressStateInsideWindow() {
        let log = """
        [
         {"when":"2026-10-29T11:59:59Z","entity_id":"lock.front","state":"locked"},
         {"when":"2026-10-30T11:59:00Z","entity_id":"lock.front","state":"locked"},
         {"when":"2026-10-30T12:00:01Z","entity_id":"lock.front","state":"unlocked"}
        ]
        """
        XCTAssertEqual(activityFrom(log, names: ["lock.front": "Front Door"], haStart: nil,
                                    windowEnd: Date(timeIntervalSince1970: 1_793_361_600)).map(\.text), ["Front Door locked"])
    }
}
