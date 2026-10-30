import XCTest
@testable import HearthKit

final class AlarmStoredSnapshotTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 100)
    private let config = HaConfig(baseUrl: "https://example.invalid", token: "inert",
        entityId: "alarm_control_panel.home", lockId: "lock.door", lockName: "Entrance")
    private func store() -> HaStateStore {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return HaStateStore(directory: directory, initialConfig: config, initialScope: "scope")
    }
    private func populate(_ store: HaStateStore) throws {
        _ = try store.merge([
            config.entityId: HaStateReading(entityID: config.entityId,
                json: #"{"entity_id":"alarm_control_panel.home","state":"disarmed","attributes":{"supported_features":3}}"#, checkedAt: now),
            config.lockId: HaStateReading(entityID: config.lockId,
                json: #"{"entity_id":"lock.door","state":"locked"}"#, checkedAt: now)
        ], expectedScope: "scope")
    }
    func testPendingAndFailedFeedbackKeepTelemetrySeparateAndSlotsStable() throws {
        let store = store(); try populate(store)
        let original = alarmStoredSnapshot(try store.snapshot(), now: now)
        let started = try XCTUnwrap(store.beginAlarmOperation(expectedScope: "scope",
            expectedRevision: original.alarmRevision, entityID: config.lockId, action: "unlock", now: now))
        let pending = alarmStoredSnapshot(started, now: now)
        XCTAssertTrue(pending.commandPending)
        XCTAssertEqual(pending.commandFeedback, "Unlocking door…")
        XCTAssertEqual(pending.stateWord, original.stateWord)
        XCTAssertEqual(pending.doorState, "Locked")
        XCTAssertEqual(pending.checkedAt, original.checkedAt)
        XCTAssertTrue(pending.actions.isEmpty)
        XCTAssertEqual(pending.actionSlots, original.actions)
        XCTAssertNil(pending.doorAction)
        let failed = try XCTUnwrap(store.finishAlarmOperation(expectedScope: "scope",
            operationID: XCTUnwrap(started.alarmOperation).id, error: "Request rejected"))
        let display = alarmStoredSnapshot(failed, now: now)
        XCTAssertFalse(display.commandPending)
        XCTAssertEqual(display.commandError, "Request rejected")
        XCTAssertEqual(display.doorState, "Locked")
        XCTAssertEqual(display.doorAction, .unlock)
        XCTAssertEqual(display.actions, original.actions)
    }
    func testDisplayAlwaysReconcilesNewReadingsEvenWithoutRevisionChange() throws {
        let store = store(); try populate(store)
        let original = alarmStoredSnapshot(try store.snapshot(), now: now)
        _ = try store.merge([config.lockId: HaStateReading(entityID: config.lockId,
            json: #"{"entity_id":"lock.door","state":"unlocked"}"#, checkedAt: now.addingTimeInterval(1))],
            expectedScope: "scope", expectedAlarmRevision: original.alarmRevision)
        let display = alarmCurrentFeedback(original, context: try store.snapshot(), now: now.addingTimeInterval(1))
        XCTAssertEqual(display.alarmRevision, original.alarmRevision)
        XCTAssertEqual(display.doorState, "Unlocked")
        XCTAssertEqual(display.doorAction, .lock)
    }
    func testSelectionChangeCannotDisplayAnotherDoorsOldSecurity() throws {
        let store = store(); try populate(store)
        let original = alarmStoredSnapshot(try store.snapshot(), now: now)
        var selected = config; selected.lockId = "lock.back"; selected.lockName = "Back entrance"
        let changed = try store.saveConfig(selected)
        let display = alarmCurrentFeedback(original, context: changed, now: now)
        XCTAssertNotEqual(display.alarmRevision, original.alarmRevision)
        XCTAssertEqual(display.doorName, "Back entrance")
        XCTAssertNil(display.doorLocked)
        XCTAssertNil(display.doorAction)
    }
    func testSignedOutAndUnreadableStorageCannotBecomeSampleHome() throws {
        let store = store(); try populate(store)
        let empty = try store.saveConfig(nil)
        let display = alarmStoredSnapshot(empty, now: now)
        XCTAssertTrue(display.setup)
        XCTAssertTrue(display.actions.isEmpty)
        XCTAssertNil(display.doorLocked)
        XCTAssertEqual(display.checkedAt, "—")
    }
}
