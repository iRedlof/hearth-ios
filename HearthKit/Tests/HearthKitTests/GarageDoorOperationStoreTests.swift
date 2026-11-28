import XCTest
@testable import HearthKit

/// The Alarm card's garage button uses the existing guarded door-command store; these cover what
/// the new garage setting adds to it.
final class GarageDoorOperationStoreTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let config = HaConfig(baseUrl: "https://home.example", token: "fixture",
        entityId: "alarm_control_panel.home", lockId: "lock.front",
        doorIdsJson: #"["binary_sensor.back"]"#, doorsChosen: true, garageId: "cover.garage")
    private func store(_ initial: HaConfig? = nil) -> HaStateStore {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return HaStateStore(directory: directory, initialConfig: initial ?? config, initialScope: "scope")
    }
    private func garage(_ state: String, at: Date) -> HaStateReading {
        HaStateReading(entityID: "cover.garage",
            json: #"{"entity_id":"cover.garage","state":"\#(state)","attributes":{"device_class":"garage","supported_features":11}}"#,
            checkedAt: at)
    }

    func testSelectedGarageCanBeCommandedWithoutBeingInTheDoorsSelection() throws {
        let store = store(), context = try store.snapshot()
        let begun = try XCTUnwrap(store.beginDoorOperation(expectedScope: context.scope,
            expectedRevision: context.doorActionRevision, entityID: "cover.garage", action: "open", now: now))
        XCTAssertEqual(begun.doorOperation?.entityID, "cover.garage")
        XCTAssertNotEqual(begun.doorActionRevision, context.doorActionRevision)
    }

    func testUnselectedCoverWrongDomainAndStaleOriginAreStillRejected() throws {
        let store = store(), context = try store.snapshot()
        for (id, action) in [("cover.other", "open"), ("cover.garage", "lock"), ("lock.front", "open")] {
            XCTAssertNil(try store.beginDoorOperation(expectedScope: context.scope,
                expectedRevision: context.doorActionRevision, entityID: id, action: action, now: now), "\(id) \(action)")
        }
        XCTAssertNil(try store.beginDoorOperation(expectedScope: "other", expectedRevision: context.doorActionRevision,
            entityID: "cover.garage", action: "open", now: now))
        XCTAssertNil(try store.beginDoorOperation(expectedScope: context.scope, expectedRevision: "stale",
            entityID: "cover.garage", action: "open", now: now))
    }

    func testChangingOrClearingTheGarageRevokesARenderedButtonAndItsPendingCommand() throws {
        for replacement in ["cover.gate", ""] {
            let store = store(), context = try store.snapshot()
            let begun = try XCTUnwrap(store.beginDoorOperation(expectedScope: context.scope,
                expectedRevision: context.doorActionRevision, entityID: "cover.garage", action: "open", now: now))
            let edited = try XCTUnwrap(store.editConfig(expectedScope: context.scope) { $0.garageId = replacement })
            XCTAssertNil(edited.doorOperation)
            XCTAssertNotEqual(edited.doorActionRevision, begun.doorActionRevision)
            XCTAssertNil(try store.claimDoorDispatch(expectedScope: context.scope,
                operationID: XCTUnwrap(begun.doorOperation).id))
            XCTAssertNil(try store.beginDoorOperation(expectedScope: context.scope,
                expectedRevision: begun.doorActionRevision, entityID: "cover.garage", action: "close", now: now))
            XCTAssertNil(try store.beginDoorOperation(expectedScope: edited.scope,
                expectedRevision: edited.doorActionRevision, entityID: "cover.garage", action: "open", now: now))
        }
    }

    func testMigratedGarageFromTheOldDoorsSelectionIsCommandable() throws {
        let legacy = HaConfig(baseUrl: "https://home.example", token: "fixture",
            entityId: "alarm_control_panel.home", doorIdsJson: #"["cover.garage","lock.front"]"#, doorsChosen: true)
        let store = store(legacy), context = try store.snapshot()
        XCTAssertEqual(context.config.flatMap(garageSelectedID), "cover.garage")
        XCTAssertNotNil(try store.beginDoorOperation(expectedScope: context.scope,
            expectedRevision: context.doorActionRevision, entityID: "cover.garage", action: "open", now: now))
    }

    func testAnAlarmRefreshThatStartedBeforeTheTapCannotReplaceTheCommandsOwnObservation() throws {
        let store = store(), context = try store.snapshot()
        let begun = try XCTUnwrap(store.beginDoorOperation(expectedScope: context.scope,
            expectedRevision: context.doorActionRevision, entityID: "cover.garage", action: "open", now: now))
        let operation = try XCTUnwrap(begun.doorOperation)
        let observed = try XCTUnwrap(store.observeDoorOperation(expectedScope: context.scope,
            operationID: operation.id, reading: garage("opening", at: now.addingTimeInterval(2))))
        XCTAssertEqual(observed.readings["cover.garage"]?.checkedAt, now.addingTimeInterval(2))

        let late = try XCTUnwrap(store.merge(["cover.garage": garage("closed", at: now.addingTimeInterval(-1))],
            expectedScope: context.scope, expectedAlarmRevision: context.alarmRevision,
            failures: ["cover.garage": "Refresh interrupted"], checkedAt: now.addingTimeInterval(-1)))
        XCTAssertEqual(late.readings["cover.garage"]?.checkedAt, now.addingTimeInterval(2))
        XCTAssertNil(late.failures["cover.garage"])
        XCTAssertEqual(late.doorOperation?.id, operation.id)
    }

    func testPendingGarageCommandDoesNotBlockPanelOrLockTelemetry() throws {
        let store = store(), context = try store.snapshot()
        _ = try XCTUnwrap(store.beginDoorOperation(expectedScope: context.scope,
            expectedRevision: context.doorActionRevision, entityID: "cover.garage", action: "open", now: now))
        let lock = HaStateReading(entityID: "lock.front",
            json: #"{"entity_id":"lock.front","state":"locked","attributes":{}}"#, checkedAt: now.addingTimeInterval(1))
        let merged = try XCTUnwrap(store.merge(["lock.front": lock], expectedScope: context.scope,
            expectedAlarmRevision: context.alarmRevision, checkedAt: now.addingTimeInterval(1)))
        XCTAssertEqual(merged.readings["lock.front"]?.checkedAt, now.addingTimeInterval(1))
    }
}
