import XCTest
@testable import HearthKit

final class AlarmFetchTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1000)
    private let config = HaConfig(baseUrl: "https://example.invalid", token: "inert",
        entityId: "alarm_control_panel.home", lockId: "lock.front", lockName: "Side entrance")
    private static let panel = #"{"entity_id":"alarm_control_panel.home","state":"disarmed","attributes":{"friendly_name":"Home Alarm","supported_features":3}}"#
    private static let door = #"{"entity_id":"lock.front","state":"locked","attributes":{"friendly_name":"Front entrance","supported_features":0}}"#

    func testMissingConfigurationAndNoDoorNeverBecomeSampleSecurity() async {
        let setup = await fetchAlarmReadings(nil, now: now)
        XCTAssertTrue(setup.snapshot(now: now).setup)
        XCTAssertNil(setup.snapshot(now: now).doorLocked)
        var noDoor = config; noDoor.lockId = ""; noDoor.lockName = ""
        let result = await fetchAlarmReadings(noDoor, now: now) { id in
            XCTAssertEqual(id, "alarm_control_panel.home")
            return Self.panel
        }
        let snapshot = result.snapshot(now: now)
        XCTAssertFalse(snapshot.doorSelected)
        XCTAssertEqual(snapshot.doorName, "No door selected")
        XCTAssertNil(snapshot.doorAction)
        XCTAssertEqual(snapshot.actions, [.armHome, .armAway])
    }

    func testSelectedNameAndZeroLockFeaturesKeepOrdinaryUnlockAvailable() async {
        let result = await fetchAlarmReadings(config, now: now) { id in id == "lock.front" ? Self.door : Self.panel }
        let snapshot = result.snapshot(now: now)
        XCTAssertEqual(snapshot.doorName, "Side entrance")
        XCTAssertEqual(snapshot.doorAction, .unlock)
        XCTAssertEqual(snapshot.doorLocked, true)
        XCTAssertEqual(snapshot.entityID, "alarm_control_panel.home")
        XCTAssertEqual(snapshot.lockID, "lock.front")
    }

    func testFailedDoorRetainsItsOwnTimeAndDoesNotInheritFreshPanel() async {
        let old = HaStateReading(entityID: "lock.front", json: Self.door,
            checkedAt: Date(timeIntervalSince1970: 400))
        let result = await fetchAlarmReadings(config, previous: ["lock.front": old], now: now) { id in
            if id == "lock.front" { throw HaError("Can't reach Home Assistant") }
            return Self.panel
        }
        let snapshot = result.snapshot(now: now)
        XCTAssertEqual(result.readings["lock.front"]?.checkedAt, Date(timeIntervalSince1970: 400))
        XCTAssertEqual(result.readings["alarm_control_panel.home"]?.checkedAt, self.now)
        XCTAssertTrue(snapshot.doorStale)
        XCTAssertEqual(snapshot.doorLocked, true)
        XCTAssertNil(snapshot.doorAction)
        XCTAssertEqual(snapshot.actions, [.armHome, .armAway])
    }

    func testFailedPanelKeepsFreshDoorIndependent() async {
        let old = HaStateReading(entityID: "alarm_control_panel.home", json: Self.panel,
            checkedAt: Date(timeIntervalSince1970: 300))
        let result = await fetchAlarmReadings(config, previous: ["alarm_control_panel.home": old], now: now) { id in
            if id == "alarm_control_panel.home" { throw HaError("Can't reach Home Assistant") }
            return Self.door
        }
        let snapshot = result.snapshot(now: now)
        XCTAssertEqual(snapshot.stateWord, "Disarmed")
        XCTAssertEqual(snapshot.tone, .offline)
        XCTAssertTrue(snapshot.actions.isEmpty)
        XCTAssertFalse(snapshot.doorStale)
        XCTAssertEqual(snapshot.doorAction, .unlock)
        XCTAssertEqual(result.readings["alarm_control_panel.home"]?.checkedAt, Date(timeIntervalSince1970: 300))
    }

    func testFreshUnavailableReplacesOldLockedInsteadOfBorrowingItsAction() async {
        let old = HaStateReading(entityID: "lock.front", json: Self.door,
            checkedAt: Date(timeIntervalSince1970: 400))
        let result = await fetchAlarmReadings(config, previous: ["lock.front": old], now: now) { id in
            id == "lock.front" ? #"{"entity_id":"lock.front","state":"unavailable"}"# : Self.panel
        }
        let snapshot = result.snapshot(now: now)
        XCTAssertFalse(snapshot.doorStale)
        XCTAssertNil(snapshot.doorLocked)
        XCTAssertNil(snapshot.doorAction)
        XCTAssertEqual(snapshot.doorState, "Unavailable")
    }

    func testMalformedAndWrongIdentityNeverBecomeSuccessfulSecurityChecks() async {
        for reply in ["{}", #"{"entity_id":"alarm_control_panel.other","state":"disarmed"}"#,
                      #"{"state":"disarmed"}"#] {
            let result = await fetchAlarmReadings(config, now: now) { id in id == "lock.front" ? Self.door : reply }
            XCTAssertNil(result.readings["alarm_control_panel.home"])
            XCTAssertNotNil(result.errors["alarm_control_panel.home"])
            XCTAssertEqual(result.snapshot(now: now).checkedAt, "—")
            XCTAssertTrue(result.snapshot(now: now).actions.isEmpty)
        }
    }

    func testArmingCapabilitiesDoNotGateDisarmOrInventSupportedModes() async {
        for (features, expected) in [(0, [AlarmAction]()), (1, [.armHome]), (2, [.armAway]), (3, [.armHome, .armAway])] {
            let reply = #"{"entity_id":"alarm_control_panel.home","state":"disarmed","attributes":{"supported_features":\#(features)}}"#
            let result = await fetchAlarmReadings(config, now: now) { id in id == "lock.front" ? Self.door : reply }
            XCTAssertEqual(result.snapshot(now: now).actions, expected)
        }
        let result = await fetchAlarmReadings(config, now: now) { id in
            id == "lock.front" ? Self.door : #"{"entity_id":"alarm_control_panel.home","state":"armed_home","attributes":{"supported_features":0}}"#
        }
        XCTAssertEqual(result.snapshot(now: now).actions, [.disarm])
    }

    func testCachedWrongIdentityCannotSupplySecurityStatusOrActions() {
        let wrongPanel = HaStateReading(entityID: config.entityId,
            json: #"{"entity_id":"alarm_control_panel.other","state":"disarmed","attributes":{"supported_features":3}}"#,
            checkedAt: now)
        let wrongLock = HaStateReading(entityID: "lock.other", json: Self.door, checkedAt: now)
        let snapshot = AlarmFetchResult(entityID: config.entityId, lockID: config.lockId,
            readings: [config.entityId: wrongPanel, config.lockId: wrongLock]).snapshot(now: now)
        XCTAssertEqual(snapshot.stateWord, "—")
        XCTAssertTrue(snapshot.actions.isEmpty)
        XCTAssertNil(snapshot.doorLocked)
        XCTAssertNil(snapshot.doorAction)
    }

    func testOldCachedReadingsAreHistoricalEvenWithoutANewFailure() {
        let old = Date(timeIntervalSince1970: 99)
        let snapshot = AlarmFetchResult(entityID: config.entityId, lockID: config.lockId, readings: [
            config.entityId: HaStateReading(entityID: config.entityId, json: Self.panel, checkedAt: old),
            config.lockId: HaStateReading(entityID: config.lockId, json: Self.door, checkedAt: old)
        ]).snapshot(now: now)
        XCTAssertEqual(snapshot.stateWord, "Disarmed")
        XCTAssertEqual(snapshot.tone, .offline)
        XCTAssertTrue(snapshot.actions.isEmpty)
        XCTAssertTrue(snapshot.doorStale)
        XCTAssertEqual(snapshot.doorLocked, true)
        XCTAssertNil(snapshot.doorAction)
    }

    func testSelectedDoorRepairDoesNotDisableHealthyPanel() async {
        let result = await fetchAlarmReadings(config, now: now) { id in
            if id == "lock.front" { throw HaError("Not found: check the entity") }
            return Self.panel
        }
        let snapshot = result.snapshot(now: now)
        XCTAssertTrue(snapshot.needsSettings)
        XCTAssertEqual(snapshot.actions, [.armHome, .armAway])
        XCTAssertNil(snapshot.doorAction)
    }
}
