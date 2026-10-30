import XCTest
@testable import HearthKit

final class HaDoorDiscoveryTests: XCTestCase {
    func testOfflineCandidatesRemainInDefaultSelectionAndNonDoorsDoNot() throws {
        let input = #"[{"entity_id":"cover.garage","state":"unavailable","attributes":{"device_class":"garage"}},{"entity_id":"binary_sensor.back","state":"unknown","attributes":{"device_class":"door","friendly_name":"Back Door"}},{"entity_id":"cover.blinds","state":"closed","attributes":{"device_class":"blind"}},{"entity_id":"binary_sensor.motion","state":"off","attributes":{"device_class":"motion"}},{"entity_id":"binary_sensor.model","state":"on","attributes":{"device_class":"door","friendly_name":"Tilt Shock Sensor"}}]"#
        XCTAssertEqual(try defaultDoorIDs(input, lockID: "lock.front"), ["cover.garage", "binary_sensor.back", "lock.front"])
    }
    func testInvalidEnvelopeIsFailureAndAnEmptyResultRemainsEmpty() throws {
        XCTAssertThrowsError(try defaultDoorIDs("{}", lockID: ""))
        XCTAssertEqual(try defaultDoorIDs("[]", lockID: ""), [])
        XCTAssertEqual(try defaultDoorIDs("[]", lockID: "switch.fake"), [])
    }
}
