import XCTest
@testable import HearthKit

final class DoorOperationStoreTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let config = HaConfig(baseUrl: "https://home.example", token: "fixture", entityId: "",
        doorIdsJson: #"["cover.garage","cover.gate","lock.front"]"#, doorsChosen: true)
    private func store() throws -> HaStateStore {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return HaStateStore(directory: directory, initialConfig: config, initialScope: "fixture")
    }
    func testSelectionAndDomainRejectBeforeCreatingAnOperation() throws {
        let store = try store(), start = try store.snapshot()
        for (id, action) in [("cover.other", "open"), ("lock.front", "open"),
                             ("cover.garage", "lock"), ("binary_sensor.door", "close")] {
            XCTAssertNil(try store.beginDoorOperation(expectedScope: start.scope, expectedRevision: start.doorActionRevision,
                entityID: id, action: action, now: now))
        }
        var other = config; other.doorIdsJson = #"["cover.other"]"#
        _ = try store.saveConfig(other); _ = try store.saveConfig(config)
        XCTAssertNil(try store.beginDoorOperation(expectedScope: start.scope, expectedRevision: start.doorActionRevision,
            entityID: "cover.garage", action: "open", now: now))
    }
    func testDeliveryIsConsumedPersistentlyBeforeTransport() throws {
        let store = try store(), start = try store.snapshot()
        let begun = try XCTUnwrap(store.beginDoorOperation(expectedScope: start.scope, expectedRevision: start.doorActionRevision,
            entityID: "cover.garage", action: "open", now: now))
        let operation = try XCTUnwrap(begun.doorOperation)
        XCTAssertFalse(operation.delivered)
        XCTAssertNotNil(try store.claimDoorDispatch(expectedScope: start.scope, operationID: operation.id))
        XCTAssertTrue(try store.snapshot().doorOperation?.delivered == true)
        XCTAssertNil(try store.claimDoorDispatch(expectedScope: start.scope, operationID: operation.id))
        _ = try store.finishDoorOperation(expectedScope: start.scope, operationID: operation.id,
            error: "Connection lost after send", now: now.addingTimeInterval(1))
        XCTAssertNil(try store.claimDoorDispatch(expectedScope: start.scope, operationID: operation.id))
    }
    func testStopOwnsItsGarageAndOlderCompletionsCannotClearIt() throws {
        let store = try store(), start = try store.snapshot()
        let open = try XCTUnwrap(store.beginDoorOperation(expectedScope: start.scope, expectedRevision: start.doorActionRevision,
            entityID: "cover.garage", action: "open", now: now)?.doorOperation)
        XCTAssertNil(try store.beginDoorOperation(expectedScope: start.scope, expectedRevision: start.doorActionRevision,
            entityID: "cover.gate", action: "stop", now: now))
        XCTAssertNil(try store.beginDoorOperation(expectedScope: start.scope, expectedRevision: start.doorActionRevision,
            entityID: "cover.garage", action: "stop", now: now))
        XCTAssertNil(try store.beginDoorOperation(expectedScope: start.scope, expectedRevision: start.doorActionRevision,
            entityID: "cover.garage", action: "stop", replacingID: "obsolete", now: now))
        let current = try store.snapshot()
        let stop = try XCTUnwrap(store.beginDoorOperation(expectedScope: start.scope, expectedRevision: current.doorActionRevision,
            entityID: "cover.garage", action: "stop", replacingID: open.id, now: now.addingTimeInterval(1))?.doorOperation)
        XCTAssertNotEqual(open.id, stop.id)
        XCTAssertNil(try store.beginDoorOperation(expectedScope: start.scope, expectedRevision: start.doorActionRevision,
            entityID: "cover.garage", action: "stop", now: now))
        XCTAssertNil(try store.finishDoorOperation(expectedScope: start.scope, operationID: open.id, error: nil))
        let old = HaStateReading(entityID: "cover.garage",
            json: #"{"entity_id":"cover.garage","state":"open","attributes":{"device_class":"garage"}}"#,
            checkedAt: now)
        XCTAssertNil(try store.observeDoorOperation(expectedScope: start.scope, operationID: open.id, reading: old))
        XCTAssertEqual(try store.snapshot().doorOperation?.id, stop.id)
    }
    func testOnlyMatchingFreshObservationsUpdateThePendingOperation() throws {
        let store = try store(), start = try store.snapshot()
        let operation = try XCTUnwrap(store.beginDoorOperation(expectedScope: start.scope, expectedRevision: start.doorActionRevision,
            entityID: "cover.garage", action: "close", now: now)?.doorOperation)
        func reading(_ rawID: String, at: Date) -> HaStateReading {
            HaStateReading(entityID: "cover.garage", json:
                #"{"entity_id":"\#(rawID)","state":"closed","attributes":{"device_class":"garage"}}"#, checkedAt: at)
        }
        XCTAssertNil(try store.observeDoorOperation(expectedScope: start.scope, operationID: operation.id,
            reading: reading("cover.other", at: now)))
        XCTAssertNil(try store.observeDoorOperation(expectedScope: start.scope, operationID: operation.id,
            reading: reading("cover.garage", at: now.addingTimeInterval(-1))))
        XCTAssertNotNil(try store.observeDoorOperation(expectedScope: start.scope, operationID: operation.id,
            reading: reading("cover.garage", at: now)))
        XCTAssertEqual(try store.snapshot().readings["cover.garage"]?.checkedAt, now)
    }
    func testInterruptedOperationExpiresWithoutReplayOrInventedTarget() throws {
        let store = try store(), start = try store.snapshot()
        let operation = try XCTUnwrap(store.beginDoorOperation(expectedScope: start.scope, expectedRevision: start.doorActionRevision,
            entityID: "cover.garage", action: "close", now: now)?.doorOperation)
        let expired = try store.expireDoorOperation(now: now.addingTimeInterval(91))
        XCTAssertFalse(expired.doorOperation?.pending == true)
        XCTAssertNotNil(expired.doorOperation?.error)
        XCTAssertTrue(expired.readings.isEmpty)
        XCTAssertNil(try store.claimDoorDispatch(expectedScope: start.scope, operationID: operation.id))
    }

    func testDoorsCannotLockWhileHomeAlarmOwnsTheSameLock() throws {
        let store = try store()
        var configured = config
        configured.entityId = "alarm_control_panel.home"
        configured.lockId = "lock.front"
        let context = try store.saveConfig(configured)
        let alarm = try XCTUnwrap(store.beginAlarmOperation(expectedScope: context.scope,
            expectedRevision: context.alarmRevision, entityID: "lock.front", action: "unlock", now: now)?.alarmOperation)
        XCTAssertNil(try store.beginDoorOperation(expectedScope: context.scope,
            expectedRevision: context.doorActionRevision, entityID: "lock.front", action: "lock", now: now))
        XCTAssertEqual(try store.snapshot().alarmOperation?.id, alarm.id)
        XCTAssertNil(try store.snapshot().doorOperation)
    }

    func testHomeAlarmCannotUnlockWhileDoorsOwnsTheSameLock() throws {
        let store = try store()
        var configured = config
        configured.entityId = "alarm_control_panel.home"
        configured.lockId = "lock.front"
        let context = try store.saveConfig(configured)
        let door = try XCTUnwrap(store.beginDoorOperation(expectedScope: context.scope,
            expectedRevision: context.doorActionRevision, entityID: "lock.front", action: "lock", now: now)?.doorOperation)
        XCTAssertNil(try store.beginAlarmOperation(expectedScope: context.scope,
            expectedRevision: context.alarmRevision, entityID: "lock.front", action: "unlock", now: now))
        XCTAssertEqual(try store.snapshot().doorOperation?.id, door.id)
        XCTAssertNil(try store.snapshot().alarmOperation)
    }

    func testUnrelatedGarageAndAlarmOperationsRemainIndependentInEitherOrder() throws {
        for alarmFirst in [false, true] {
            let store = try store()
            var configured = config
            configured.entityId = "alarm_control_panel.home"
            let context = try store.saveConfig(configured)
            if alarmFirst {
                XCTAssertNotNil(try store.beginAlarmOperation(expectedScope: context.scope,
                    expectedRevision: context.alarmRevision, entityID: "alarm_control_panel.home", action: "armHome", now: now))
                XCTAssertNotNil(try store.beginDoorOperation(expectedScope: context.scope,
                    expectedRevision: context.doorActionRevision, entityID: "cover.garage", action: "open", now: now))
            } else {
                XCTAssertNotNil(try store.beginDoorOperation(expectedScope: context.scope,
                    expectedRevision: context.doorActionRevision, entityID: "cover.garage", action: "open", now: now))
                XCTAssertNotNil(try store.beginAlarmOperation(expectedScope: context.scope,
                    expectedRevision: context.alarmRevision, entityID: "alarm_control_panel.home", action: "armHome", now: now))
            }
            XCTAssertTrue(try store.snapshot().doorOperation?.pending == true)
            XCTAssertTrue(try store.snapshot().alarmOperation?.pending == true)
        }
    }

    func testDoorsLockExpiresOnlyAStaleOrFutureHomeAlarmOwnerOfTheSameEntity() throws {
        for startedAt in [now.addingTimeInterval(-91), now.addingTimeInterval(1)] {
            let store = try store()
            var configured = config
            configured.entityId = "alarm_control_panel.home"
            configured.lockId = "lock.front"
            let context = try store.saveConfig(configured)
            let begun = try XCTUnwrap(store.beginAlarmOperation(expectedScope: context.scope,
                expectedRevision: context.alarmRevision, entityID: "lock.front", action: "unlock", now: startedAt))
            let alarm = try XCTUnwrap(begun.alarmOperation)
            let next = try XCTUnwrap(store.beginDoorOperation(expectedScope: context.scope,
                expectedRevision: context.doorActionRevision, entityID: "lock.front", action: "lock", now: now))
            XCTAssertTrue(next.doorOperation?.pending == true)
            XCTAssertEqual(next.alarmOperation?.id, alarm.id)
            XCTAssertFalse(next.alarmOperation?.pending == true)
            XCTAssertNotNil(next.alarmOperation?.error)
            XCTAssertNotEqual(next.alarmRevision, begun.alarmRevision)
        }
    }

    func testHomeAlarmUnlockExpiresOnlyAStaleOrFutureDoorsOwnerOfTheSameEntity() throws {
        for startedAt in [now.addingTimeInterval(-91), now.addingTimeInterval(1)] {
            let store = try store()
            var configured = config
            configured.entityId = "alarm_control_panel.home"
            configured.lockId = "lock.front"
            let context = try store.saveConfig(configured)
            let door = try XCTUnwrap(store.beginDoorOperation(expectedScope: context.scope,
                expectedRevision: context.doorActionRevision, entityID: "lock.front", action: "lock", now: startedAt)?.doorOperation)
            let next = try XCTUnwrap(store.beginAlarmOperation(expectedScope: context.scope,
                expectedRevision: context.alarmRevision, entityID: "lock.front", action: "unlock", now: now))
            XCTAssertTrue(next.alarmOperation?.pending == true)
            XCTAssertEqual(next.doorOperation?.id, door.id)
            XCTAssertFalse(next.doorOperation?.pending == true)
            XCTAssertNotNil(next.doorOperation?.error)
            XCTAssertEqual(next.doorOperation?.endedAt, now)
        }
    }

    func testStartingAnUnrelatedOperationDoesNotExpireTheOtherSlot() throws {
        let store = try store()
        var configured = config
        configured.entityId = "alarm_control_panel.home"
        let context = try store.saveConfig(configured)
        let garage = try XCTUnwrap(store.beginDoorOperation(expectedScope: context.scope,
            expectedRevision: context.doorActionRevision, entityID: "cover.garage", action: "open",
            now: now.addingTimeInterval(-91))?.doorOperation)
        let next = try XCTUnwrap(store.beginAlarmOperation(expectedScope: context.scope,
            expectedRevision: context.alarmRevision, entityID: "alarm_control_panel.home", action: "armHome", now: now))
        XCTAssertEqual(next.doorOperation?.id, garage.id)
        XCTAssertTrue(next.doorOperation?.pending == true)
        XCTAssertNil(next.doorOperation?.error)

        let anotherStore = try self.store()
        let otherContext = try anotherStore.saveConfig(configured)
        let alarm = try XCTUnwrap(anotherStore.beginAlarmOperation(expectedScope: otherContext.scope,
            expectedRevision: otherContext.alarmRevision, entityID: "alarm_control_panel.home", action: "armHome",
            now: now.addingTimeInterval(-91))?.alarmOperation)
        let otherNext = try XCTUnwrap(anotherStore.beginDoorOperation(expectedScope: otherContext.scope,
            expectedRevision: otherContext.doorActionRevision, entityID: "cover.garage", action: "open", now: now))
        XCTAssertEqual(otherNext.alarmOperation?.id, alarm.id)
        XCTAssertTrue(otherNext.alarmOperation?.pending == true)
        XCTAssertNil(otherNext.alarmOperation?.error)
    }

    func testDoorObservationPreservesANewerSharedLockFailure() throws {
        let store = try store(), context = try store.snapshot()
        let operation = try XCTUnwrap(store.beginDoorOperation(expectedScope: context.scope,
            expectedRevision: context.doorActionRevision, entityID: "lock.front", action: "lock", now: now)?.doorOperation)
        _ = try store.merge([:], expectedScope: context.scope, failures: ["lock.front": "Later read failed"],
            checkedAt: now.addingTimeInterval(2))
        let reading = HaStateReading(entityID: "lock.front",
            json: #"{"entity_id":"lock.front","state":"locked","attributes":{}}"#,
            checkedAt: now.addingTimeInterval(1))
        let observed = try XCTUnwrap(store.observeDoorOperation(expectedScope: context.scope,
            operationID: operation.id, reading: reading))
        XCTAssertEqual(observed.readings["lock.front"]?.checkedAt, now.addingTimeInterval(1))
        XCTAssertEqual(observed.failures["lock.front"]?.message, "Later read failed")
        XCTAssertEqual(observed.failures["lock.front"]?.checkedAt, now.addingTimeInterval(2))
    }

    func testDoorObservationClearsOnlyAnOlderOrSameTimeSharedLockFailure() throws {
        for failureTime in [now, now.addingTimeInterval(1)] {
            let store = try store(), context = try store.snapshot()
            let operation = try XCTUnwrap(store.beginDoorOperation(expectedScope: context.scope,
                expectedRevision: context.doorActionRevision, entityID: "lock.front", action: "lock", now: now)?.doorOperation)
            _ = try store.merge([:], expectedScope: context.scope, failures: ["lock.front": "Earlier read failed"],
                checkedAt: failureTime)
            let reading = HaStateReading(entityID: "lock.front",
                json: #"{"entity_id":"lock.front","state":"locked","attributes":{}}"#,
                checkedAt: now.addingTimeInterval(1))
            let observed = try XCTUnwrap(store.observeDoorOperation(expectedScope: context.scope,
                operationID: operation.id, reading: reading))
            XCTAssertNil(observed.failures["lock.front"])
        }
    }

    func testRenderedOpenCannotReplayAfterOwnedStopFinishedOnKnownClosedGarage() throws {
        let store = try store(), rendered = try store.snapshot()
        let begun = try XCTUnwrap(store.beginDoorOperation(expectedScope: rendered.scope,
            expectedRevision: rendered.doorActionRevision, entityID: "cover.garage", action: "open", now: now))
        let open = try XCTUnwrap(begun.doorOperation)
        XCTAssertNotEqual(begun.doorActionRevision, rendered.doorActionRevision)
        XCTAssertEqual(begun.collectionRevision, rendered.collectionRevision)
        let stopped = try XCTUnwrap(store.beginDoorOperation(expectedScope: rendered.scope,
            expectedRevision: begun.doorActionRevision, entityID: "cover.garage", action: "stop",
            replacingID: open.id, now: now.addingTimeInterval(1)))
        let stop = try XCTUnwrap(stopped.doorOperation)
        let closed = HaStateReading(entityID: "cover.garage",
            json: #"{"entity_id":"cover.garage","state":"closed","attributes":{"device_class":"garage"}}"#,
            checkedAt: now.addingTimeInterval(2))
        _ = try store.observeDoorOperation(expectedScope: rendered.scope, operationID: stop.id, reading: closed)
        _ = try store.finishDoorOperation(expectedScope: rendered.scope, operationID: stop.id,
            error: nil, now: now.addingTimeInterval(2))
        XCTAssertNil(try store.beginDoorOperation(expectedScope: rendered.scope,
            expectedRevision: rendered.doorActionRevision, entityID: "cover.garage", action: "open",
            now: now.addingTimeInterval(3)))
        let refreshed = try store.snapshot()
        XCTAssertNotNil(try store.beginDoorOperation(expectedScope: refreshed.scope,
            expectedRevision: refreshed.doorActionRevision, entityID: "cover.garage", action: "open",
            now: now.addingTimeInterval(3)))
    }

    func testDoorActionConsumptionDoesNotInvalidateUnrelatedCollectionReads() throws {
        let store = try store(), context = try store.snapshot()
        let read = try XCTUnwrap(store.beginCollectionRead("batteries", expectedScope: context.scope,
            expectedRevision: context.collectionRevision))
        let begun = try XCTUnwrap(store.beginDoorOperation(expectedScope: context.scope,
            expectedRevision: context.doorActionRevision, entityID: "cover.garage", action: "open", now: now))
        XCTAssertNotEqual(begun.doorActionRevision, context.doorActionRevision)
        XCTAssertEqual(begun.collectionRevision, context.collectionRevision)
        XCTAssertNotNil(try store.mergeCollection("batteries", reply: .success("[]"),
            expectedScope: context.scope, expectedRevision: context.collectionRevision, readID: read, now: now))
        XCTAssertEqual(try store.snapshot().doorActionRevision, begun.doorActionRevision)
    }

    func testActionRevisionRotatesOnSourceAccountAndDiscoveryButPreservesPreferences() throws {
        let store = try store(), initial = try store.snapshot()
        var preference = config; preference.lockName = "Entry"; preference.confirmWith = CONFIRM_DIALOG
        let edited = try store.saveConfig(preference)
        XCTAssertEqual(edited.doorActionRevision, initial.doorActionRevision)
        var selected = preference; selected.doorIdsJson = #"["cover.gate"]"#
        let changed = try store.saveConfig(selected)
        XCTAssertNotEqual(changed.doorActionRevision, edited.doorActionRevision)
        let back = try store.saveConfig(preference)
        XCTAssertNotEqual(back.doorActionRevision, initial.doorActionRevision)
        let signedOut = try store.saveConfig(nil)
        let signedIn = try store.saveConfig(preference)
        XCTAssertNotEqual(signedIn.doorActionRevision, back.doorActionRevision)
        XCTAssertNotEqual(signedIn.doorActionRevision, signedOut.doorActionRevision)
        var unchosen = preference; unchosen.doorIdsJson = "[]"; unchosen.doorsChosen = false
        let discovery = try store.saveConfig(unchosen)
        let read = try XCTUnwrap(store.beginCollectionRead("doors", expectedScope: discovery.scope,
            expectedRevision: discovery.collectionRevision))
        let adopted = try XCTUnwrap(store.adoptDoorDiscovery(["cover.garage"], expectedScope: discovery.scope,
            expectedRevision: discovery.collectionRevision, readID: read))
        XCTAssertNotEqual(adopted.doorActionRevision, discovery.doorActionRevision)
    }

    func testLegacyActionRevisionIsStableAcrossProcessesAndPersistedByAnUnrelatedEdit() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let store = HaStateStore(directory: directory, initialConfig: config, initialScope: "legacy-account")
        let initial = try store.snapshot()
        let file = directory.appendingPathComponent("ha-state.json")
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any])
        object.removeValue(forKey: "doorActionRevision")
        try JSONSerialization.data(withJSONObject: object).write(to: file)
        let first = try store.snapshot()
        let second = try HaStateStore(directory: directory).snapshot()
        XCTAssertEqual(first.doorActionRevision, second.doorActionRevision)
        XCTAssertNotEqual(first.doorActionRevision, initial.collectionRevision)
        var preference = config; preference.lockName = "Entry"
        let saved = try store.saveConfig(preference)
        XCTAssertEqual(saved.doorActionRevision, first.doorActionRevision)
        let persisted = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any])
        XCTAssertEqual(persisted["doorActionRevision"] as? String, first.doorActionRevision)
        XCTAssertNil(try store.beginDoorOperation(expectedScope: first.scope,
            expectedRevision: initial.collectionRevision, entityID: "cover.garage", action: "open", now: now))
    }
}
