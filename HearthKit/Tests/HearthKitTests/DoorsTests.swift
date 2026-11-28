import XCTest
@testable import HearthKit

/// The door model the guarded command path, Activity and the Alarm card's garage row share.
final class DoorsTests: XCTestCase {
    func testDoorActionsAreDirectTaps() {
        XCTAssertFalse(DoorAction.open.needsConfirm)
        XCTAssertFalse(DoorAction.close.needsConfirm)
        XCTAssertFalse(DoorAction.stop.needsConfirm)
        XCTAssertFalse(DoorAction.lock.needsConfirm)
    }

    func testGarageAndGateKeepDistinctFriendlyNames() {
        XCTAssertEqual(doorFromState(#"{"entity_id":"cover.east","state":"closed","attributes":{"device_class":"garage","friendly_name":"East Garage"}}"#)?.name, "East Garage")
        XCTAssertEqual(doorFromState(#"{"entity_id":"cover.side","state":"open","attributes":{"device_class":"gate","friendly_name":"Side Gate"}}"#)?.name, "Side Gate")
    }

    func testUnrelatedCoversAndSensorsCannotBecomeDoors() {
        XCTAssertNil(doorFromState(#"{"entity_id":"cover.blind","state":"closed","attributes":{"device_class":"blind"}}"#))
        XCTAssertNil(doorFromState(#"{"entity_id":"binary_sensor.motion","state":"off","attributes":{"device_class":"motion"}}"#))
    }

    func testMalformedStateTypesAndEmptyIdentityAreRejected() {
        XCTAssertNil(doorFromState(#"{"entity_id":"cover.garage","state":1,"attributes":{"device_class":"garage"}}"#))
        XCTAssertNil(doorFromState(#"{"entity_id":"cover.","state":"closed","attributes":{"device_class":"garage"}}"#))
        XCTAssertNil(doorFromState(#"{"entity_id":"lock.front","state":null,"attributes":{}}"#))
    }

    func testStopRequiresKnownOpenOrClosedPosition() {
        for state in ["unknown", "unavailable", "opening", "closing", "jammed", ""] {
            XCTAssertFalse(DoorAction.stop.done(state), state)
        }
        XCTAssertFalse(DoorAction.stop.done(nil))
        XCTAssertTrue(DoorAction.stop.done("closed"))
        XCTAssertTrue(DoorAction.stop.done("open"))
    }

    func testStopCapabilityPreservesMissingVersusUnsupportedAndMalformedMask() throws {
        for (raw, expected) in [(nil, nil), ("8", true), ("3", false), ("true", false),
                                ("null", false), (#""8""#, false), ("-1", false), ("1.5", false)] as [(String?, Bool?)] {
            let mask = raw.map { #","supported_features":\#($0)"# } ?? ""
            let json = #"{"entity_id":"cover.garage","state":"unknown","attributes":{"device_class":"garage"\#(mask)}}"#
            XCTAssertEqual(try XCTUnwrap(doorFromState(json)).supportsStop, expected, raw ?? "missing")
        }
    }

    func testDoorActionRoundTripsThroughTheAlarmSnapshot() throws {
        for action in [DoorAction.open, .close, .stop, .lock] {
            let decoded = try JSONDecoder().decode(DoorAction.self, from: JSONEncoder().encode(action))
            XCTAssertEqual(decoded, action)
        }
    }
}
