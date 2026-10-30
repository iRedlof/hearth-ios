import XCTest
@testable import HearthKit

final class AlarmOperationTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 100)
    private let config = HaConfig(baseUrl: "https://example.com", token: "fixture",
        entityId: "alarm_control_panel.home", lockId: "lock.front", climateId: "climate.room")
    private func store() -> HaStateStore {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return HaStateStore(directory: directory, initialConfig: config, initialScope: "scope")
    }
    private func reading(_ id: String, _ state: String = "disarmed", at: TimeInterval = 90) -> HaStateReading {
        HaStateReading(entityID: id, json: "{\"entity_id\":\"\(id)\",\"state\":\"\(state)\",\"attributes\":{\"supported_features\":3}}",
            checkedAt: Date(timeIntervalSince1970: at))
    }
    private func begin(_ store: HaStateStore, revision: String, entity: String = "alarm_control_panel.home",
                       action: String = "armHome") throws -> HaStoreSnapshot? {
        try store.beginAlarmOperation(expectedScope: "scope", expectedRevision: revision,
            entityID: entity, action: action, now: now)
    }

    func testDuplicateTapOldRevisionAndWrongDomainAreRejectedAtomically() throws {
        let store = store(), before = try store.snapshot()
        XCTAssertNil(try begin(store, revision: before.alarmRevision, entity: "lock.front"))
        let started = try XCTUnwrap(begin(store, revision: before.alarmRevision))
        XCTAssertNotEqual(before.alarmRevision, started.alarmRevision)
        XCTAssertNil(try begin(store, revision: before.alarmRevision))
        XCTAssertNil(try begin(store, revision: started.alarmRevision, entity: "lock.front", action: "unlock"))
        let settled = try XCTUnwrap(store.finishAlarmOperation(expectedScope: "scope",
            operationID: XCTUnwrap(started.alarmOperation).id, error: nil))
        XCTAssertNil(try begin(store, revision: before.alarmRevision))
        XCTAssertNotNil(try begin(store, revision: settled.alarmRevision, entity: "lock.front", action: "unlock"))
    }

    func testPanelAndDoorSelectionChangesRevokeBothOriginsIncludingAToBToA() throws {
        for changeDoor in [false, true] {
            let store = store(), before = try store.snapshot()
            let started = try XCTUnwrap(begin(store, revision: before.alarmRevision))
            var other = config
            if changeDoor { other.lockId = "lock.back" } else { other.entityId = "alarm_control_panel.other" }
            _ = try store.saveConfig(other)
            let returned = try store.saveConfig(config)
            XCTAssertEqual(returned.scope, before.scope)
            XCTAssertNotEqual(returned.alarmRevision, before.alarmRevision)
            XCTAssertNil(returned.alarmOperation)
            XCTAssertNil(try begin(store, revision: before.alarmRevision))
            XCTAssertNil(try store.finishAlarmOperation(expectedScope: "scope",
                operationID: XCTUnwrap(started.alarmOperation).id, error: nil))
        }
    }

    func testAlarmChangesPreserveClimateOperationAndViceVersa() throws {
        let store = store(), before = try store.snapshot()
        let climate = try XCTUnwrap(store.beginClimateOperation(expectedScope: "scope",
            expectedRevision: before.climateRevision, entityID: "climate.room", action: "heatUp", now: now))
        var renamed = config; renamed.lockName = "Entrance"
        let renamedResult = try store.saveConfig(renamed)
        XCTAssertEqual(renamedResult.alarmRevision, before.alarmRevision)
        let alarm = try XCTUnwrap(begin(store, revision: before.alarmRevision))
        XCTAssertEqual(alarm.climateOperation?.id, climate.climateOperation?.id)
        XCTAssertEqual(alarm.climateRevision, climate.climateRevision)
        var changed = renamed; changed.climateId = "climate.other"
        let updated = try store.saveConfig(changed)
        XCTAssertEqual(updated.alarmOperation?.id, alarm.alarmOperation?.id)
        XCTAssertEqual(updated.alarmRevision, alarm.alarmRevision)
        changed.lockId = "lock.other"
        XCTAssertNil(try store.saveConfig(changed).alarmOperation)
    }

    func testRefreshCannotRestorePanelOrLockControlsAcrossCommandBoundary() throws {
        let store = store()
        _ = try store.merge(["alarm_control_panel.home": reading("alarm_control_panel.home"),
                             "lock.front": reading("lock.front", "locked")], expectedScope: "scope")
        let before = try store.snapshot(), started = try XCTUnwrap(begin(store, revision: before.alarmRevision))
        let during = try XCTUnwrap(store.merge([
            "alarm_control_panel.home": reading("alarm_control_panel.home", "armed_home", at: 110),
            "lock.front": reading("lock.front", "unlocked", at: 110),
            "sensor.room": reading("sensor.room", "70", at: 110)
        ], expectedScope: "scope", expectedAlarmRevision: before.alarmRevision,
           failures: ["lock.front": "Old failure"], checkedAt: Date(timeIntervalSince1970: 110)))
        XCTAssertEqual(during.readings["alarm_control_panel.home"]?.checkedAt, Date(timeIntervalSince1970: 90))
        XCTAssertEqual(during.readings["lock.front"]?.checkedAt, Date(timeIntervalSince1970: 90))
        XCTAssertNotNil(during.readings["sensor.room"])
        XCTAssertNil(during.failures["lock.front"])
        _ = try store.finishAlarmOperation(expectedScope: "scope",
            operationID: XCTUnwrap(started.alarmOperation).id, error: nil)
        let late = try XCTUnwrap(store.merge(["lock.front": reading("lock.front", "unlocked", at: 120)],
            expectedScope: "scope", expectedAlarmRevision: before.alarmRevision))
        XCTAssertEqual(late.readings["lock.front"]?.checkedAt, Date(timeIntervalSince1970: 90))
    }

    func testOwnedObservationsUpdateActualStateAndObsoleteCompletionsCannotSettleNewWork() throws {
        let store = store(), before = try store.snapshot()
        let started = try XCTUnwrap(begin(store, revision: before.alarmRevision))
        let id = try XCTUnwrap(started.alarmOperation).id
        XCTAssertNil(try store.observeAlarmOperation(expectedScope: "scope", operationID: id,
            reading: reading("lock.front", "locked", at: 101)))
        let observed = try XCTUnwrap(store.observeAlarmOperation(expectedScope: "scope", operationID: id,
            reading: reading("alarm_control_panel.home", "arming", at: 101)))
        XCTAssertEqual(AlarmState.fromJson(try XCTUnwrap(observed.readings[config.entityId]).json)?.state, "arming")
        XCTAssertTrue(try XCTUnwrap(observed.alarmOperation).pending)
        let failed = try XCTUnwrap(store.finishAlarmOperation(expectedScope: "scope", operationID: id,
            error: "Couldn't confirm · Refresh to check"))
        let newer = try XCTUnwrap(begin(store, revision: failed.alarmRevision, action: "disarm"))
        XCTAssertNil(try store.observeAlarmOperation(expectedScope: "scope", operationID: id,
            reading: reading(config.entityId, "armed_home", at: 120)))
        XCTAssertNil(try store.finishAlarmOperation(expectedScope: "scope", operationID: id, error: nil))
        XCTAssertEqual(try store.snapshot().alarmOperation?.id, newer.alarmOperation?.id)
    }

    func testInterruptedOperationExpiresWithoutInventingSuccessfulCheckOrRetry() throws {
        let store = store()
        _ = try store.merge([config.entityId: reading(config.entityId)], expectedScope: "scope")
        let started = try XCTUnwrap(begin(store, revision: store.snapshot().alarmRevision))
        let expired = try store.expireAlarmOperation(now: now.addingTimeInterval(91))
        XCTAssertFalse(try XCTUnwrap(expired.alarmOperation).pending)
        XCTAssertEqual(expired.readings[config.entityId]?.checkedAt, Date(timeIntervalSince1970: 90))
        XCTAssertNotEqual(expired.alarmRevision, started.alarmRevision)
        XCTAssertNil(try store.finishAlarmOperation(expectedScope: "scope",
            operationID: XCTUnwrap(started.alarmOperation).id, error: nil))
    }

    func testSimultaneousClaimsHaveExactlyOneWinner() throws {
        let store = store(), revision = try store.snapshot().alarmRevision
        let winners = AlarmClaimCounter()
        DispatchQueue.concurrentPerform(iterations: 24) { _ in
            do {
                if try store.beginAlarmOperation(expectedScope: "scope", expectedRevision: revision,
                    entityID: "alarm_control_panel.home", action: "armHome") != nil { winners.increment() }
            } catch { XCTFail("\(error)") }
        }
        XCTAssertEqual(winners.count, 1)
    }

    func testReadFailureIsOwnedAndFreshObservationClearsOnlyThatEntityFailure() throws {
        let store = store(), revision = try store.snapshot().alarmRevision
        let started = try XCTUnwrap(begin(store, revision: revision))
        let id = try XCTUnwrap(started.alarmOperation).id
        _ = try store.failAlarmOperationRead(expectedScope: "scope", operationID: id,
            message: "Not reachable", checkedAt: now)
        XCTAssertNotNil(try store.snapshot().failures[config.entityId])
        let observed = try XCTUnwrap(store.observeAlarmOperation(expectedScope: "scope", operationID: id,
            reading: reading(config.entityId, "arming", at: 101)))
        XCTAssertNil(observed.failures[config.entityId])
        let settled = try XCTUnwrap(store.finishAlarmOperation(expectedScope: "scope", operationID: id, error: nil))
        let newer = try XCTUnwrap(begin(store, revision: settled.alarmRevision, entity: config.lockId, action: "unlock"))
        XCTAssertNil(try store.failAlarmOperationRead(expectedScope: "scope", operationID: id, message: "Old failure"))
        XCTAssertEqual(try store.snapshot().alarmOperation?.id, newer.alarmOperation?.id)
        XCTAssertNil(try store.snapshot().failures[config.entityId])
    }
}

private final class AlarmClaimCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0
    var count: Int { lock.lock(); defer { lock.unlock() }; return value }
    func increment() { lock.lock(); defer { lock.unlock() }; value += 1 }
}
