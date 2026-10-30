import XCTest
@testable import HearthKit

final class ClimateOperationTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 100)
    private let config = HaConfig(baseUrl: "https://example.com", token: "fixture", entityId: "",
                                  climateId: "climate.room", resumeId: "button.resume")
    private func store() throws -> HaStateStore {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return HaStateStore(directory: directory, initialConfig: config, initialScope: "scope")
    }
    private func reading(_ id: String, at: TimeInterval) -> HaStateReading {
        HaStateReading(entityID: id, json: #"{"state":"heat","attributes":{"temperature":70}}"#,
                       checkedAt: Date(timeIntervalSince1970: at))
    }
    private func begin(_ store: HaStateStore, revision: String) throws -> HaStoreSnapshot? {
        try store.beginClimateOperation(expectedScope: "scope", expectedRevision: revision,
            entityID: config.climateId, action: "heatUp", now: now)
    }

    func testDuplicateTapAndObsoleteRenderedRevisionCannotStartAnotherCommand() throws {
        let store = try store()
        let initial = try store.snapshot()
        let started = try XCTUnwrap(begin(store, revision: initial.climateRevision))
        XCTAssertNotEqual(started.climateRevision, initial.climateRevision)
        XCTAssertNil(try begin(store, revision: initial.climateRevision))
        XCTAssertNil(try begin(store, revision: started.climateRevision))
        let operation = try XCTUnwrap(started.climateOperation)
        let finished = try XCTUnwrap(store.finishClimateOperation(expectedScope: "scope",
            operationID: operation.id, error: nil))
        XCTAssertNil(finished.climateOperation)
        XCTAssertNil(try begin(store, revision: initial.climateRevision))
        XCTAssertNotNil(try begin(store, revision: finished.climateRevision))
    }

    func testOnlyMatchingCommandCanSettleAndFailedCommandKeepsReadings() throws {
        let store = try store()
        _ = try store.merge(["climate.room": reading("climate.room", at: 90)], expectedScope: "scope")
        let started = try XCTUnwrap(begin(store, revision: store.snapshot().climateRevision))
        XCTAssertNil(try store.finishClimateOperation(expectedScope: "scope", operationID: "wrong", error: nil))
        let failed = try XCTUnwrap(store.finishClimateOperation(expectedScope: "scope",
            operationID: XCTUnwrap(started.climateOperation).id, error: "Can't reach Home Assistant"))
        XCTAssertEqual(failed.climateOperation?.error, "Can't reach Home Assistant")
        XCTAssertEqual(failed.readings["climate.room"]?.checkedAt, Date(timeIntervalSince1970: 90))
        XCTAssertNotNil(try begin(store, revision: failed.climateRevision))
    }

    func testOldPollCannotReplaceClimateButItsIndependentSensorsCanMerge() throws {
        let store = try store()
        _ = try store.merge(["climate.room": reading("climate.room", at: 90)], expectedScope: "scope")
        let before = try store.snapshot()
        let started = try XCTUnwrap(begin(store, revision: before.climateRevision))
        let merged = try XCTUnwrap(store.merge([
            "climate.room": reading("climate.room", at: 101), "sensor.room": reading("sensor.room", at: 101)
        ], expectedScope: "scope", expectedClimateRevision: before.climateRevision))
        XCTAssertEqual(merged.readings["climate.room"]?.checkedAt, Date(timeIntervalSince1970: 90))
        XCTAssertEqual(merged.readings["sensor.room"]?.checkedAt, Date(timeIntervalSince1970: 101))
        let during = try XCTUnwrap(store.merge(["climate.room": reading("climate.room", at: 102)],
            expectedScope: "scope", expectedClimateRevision: started.climateRevision))
        XCTAssertEqual(during.readings["climate.room"]?.checkedAt, Date(timeIntervalSince1970: 90))
        _ = try store.finishClimateOperation(expectedScope: "scope",
            operationID: XCTUnwrap(started.climateOperation).id, error: nil)
        let after = try XCTUnwrap(store.merge(["climate.room": reading("climate.room", at: 103)],
            expectedScope: "scope", expectedClimateRevision: before.climateRevision))
        XCTAssertEqual(after.readings["climate.room"]?.checkedAt, Date(timeIntervalSince1970: 90))
        let fresh = try XCTUnwrap(store.merge(["climate.room": reading("climate.room", at: 104)],
            expectedScope: "scope", expectedClimateRevision: after.climateRevision))
        XCTAssertEqual(fresh.readings["climate.room"]?.checkedAt, Date(timeIntervalSince1970: 104))
    }

    func testSelectionChangesRevokeOldActionsIncludingSelectingSameDeviceAgain() throws {
        let store = try store()
        let before = try store.snapshot()
        let started = try XCTUnwrap(begin(store, revision: before.climateRevision))
        var other = config; other.climateId = "climate.other"
        _ = try store.saveConfig(other)
        let returned = try store.saveConfig(config)
        XCTAssertEqual(returned.scope, before.scope)
        XCTAssertNotEqual(returned.climateRevision, before.climateRevision)
        XCTAssertNil(returned.climateOperation)
        XCTAssertNil(try begin(store, revision: before.climateRevision))
        XCTAssertNil(try store.finishClimateOperation(expectedScope: "scope",
            operationID: XCTUnwrap(started.climateOperation).id, error: nil))
    }

    func testAbandonedCommandExpiresWithoutChangingTheSuccessfulCheckTime() throws {
        let store = try store()
        _ = try store.merge(["climate.room": reading("climate.room", at: 90)], expectedScope: "scope")
        let started = try XCTUnwrap(begin(store, revision: store.snapshot().climateRevision))
        let expired = try store.expireClimateOperation(now: now.addingTimeInterval(91))
        XCTAssertFalse(try XCTUnwrap(expired.climateOperation).pending)
        XCTAssertNotNil(expired.climateOperation?.error)
        XCTAssertNotEqual(expired.climateRevision, started.climateRevision)
        XCTAssertEqual(expired.readings["climate.room"]?.checkedAt, Date(timeIntervalSince1970: 90))
        XCTAssertNil(try store.finishClimateOperation(expectedScope: "scope",
            operationID: XCTUnwrap(started.climateOperation).id, error: nil))
        XCTAssertNotNil(try begin(store, revision: expired.climateRevision))
    }

    func testCommandFeedbackCannotMakeAFailedSensorCurrentAgain() throws {
        let store = try store()
        _ = try store.merge(["sensor.room": reading("sensor.room", at: 80)], expectedScope: "scope")
        _ = try store.merge([:], expectedScope: "scope",
            failures: ["sensor.room": "Not reachable"], checkedAt: Date(timeIntervalSince1970: 90))
        let started = try XCTUnwrap(begin(store, revision: store.snapshot().climateRevision))
        XCTAssertEqual(started.failures["sensor.room"]?.message, "Not reachable")
        let finished = try XCTUnwrap(store.finishClimateOperation(expectedScope: "scope",
            operationID: XCTUnwrap(started.climateOperation).id, error: nil))
        XCTAssertEqual(finished.failures["sensor.room"]?.message, "Not reachable")
        XCTAssertEqual(finished.readings["sensor.room"]?.checkedAt, Date(timeIntervalSince1970: 80))
    }

    func testObsoleteClimateFailureIsRejectedAndAnOlderSensorFailureCannotUndoFreshSuccess() throws {
        let store = try store()
        let before = try store.snapshot()
        _ = try begin(store, revision: before.climateRevision)
        _ = try store.merge(["sensor.room": reading("sensor.room", at: 120)], expectedScope: "scope")
        let updated = try XCTUnwrap(store.merge([:], expectedScope: "scope",
            expectedClimateRevision: before.climateRevision,
            failures: ["climate.room": "Old failure", "sensor.room": "Old failure"],
            checkedAt: Date(timeIntervalSince1970: 110)))
        XCTAssertNil(updated.failures["climate.room"])
        XCTAssertNil(updated.failures["sensor.room"])
        _ = try store.merge([:], expectedScope: "scope", failures: ["sensor.room": "Newest failure"],
            checkedAt: Date(timeIntervalSince1970: 130))
        let lateSuccess = try XCTUnwrap(store.merge(["sensor.room": reading("sensor.room", at: 125)],
            expectedScope: "scope"))
        XCTAssertEqual(lateSuccess.failures["sensor.room"]?.message, "Newest failure")
        let recovered = try XCTUnwrap(store.merge(["sensor.room": reading("sensor.room", at: 140)],
            expectedScope: "scope"))
        XCTAssertNil(recovered.failures["sensor.room"])
    }

    func testFeedbackPreservesTelemetryAndDisablesControlsOnlyWhilePending() {
        var original = ThermostatSnapshot.sample
        original.canAdjustHeatUp = true; original.canPickMode = true
        let pending = ClimateOperation(entityID: config.climateId, action: "heatUp", startedAt: now)
        let display = climateApplyingOperation(original, pending)
        XCTAssertTrue(display.commandPending)
        XCTAssertFalse(display.canAdjustHeatUp)
        XCTAssertFalse(display.canPickMode)
        XCTAssertFalse(display.canResume)
        XCTAssertEqual(display.status, original.status)
        XCTAssertEqual(display.checkedAt, original.checkedAt)
        XCTAssertEqual(display.heatSetpoint, original.heatSetpoint)
        var failed = pending; failed.error = "Not reachable"
        let failure = climateApplyingOperation(original, failed)
        XCTAssertFalse(failure.commandPending)
        XCTAssertTrue(failure.canAdjustHeatUp)
        XCTAssertTrue(failure.canResume)
        XCTAssertEqual(failure.commandError, "Not reachable")
        XCTAssertEqual(failure.status, original.status)
        XCTAssertEqual(failure.sensors, original.sensors)
    }

    func testPendingFeedbackKeepsAdvertisedFanAndResumeSlotsVisible() throws {
        let state = try XCTUnwrap(ClimateState.fromJson(#"{"state":"heat","attributes":{"temperature":68,"fan_modes":["auto","on"],"hvac_modes":["off","heat"]}}"#))
        let original = thermostatSnapshot(state, name: "Thermostat", now: now, stale: false,
            checkedAt: now, canResume: true)
        XCTAssertNil(original.fan)
        XCTAssertTrue(original.hasFanControl)
        XCTAssertTrue(original.canPickFan)
        let pending = climateApplyingOperation(original,
            ClimateOperation(entityID: config.climateId, action: "heatUp", startedAt: now))
        XCTAssertTrue(pending.hasFanControl)
        XCTAssertTrue(pending.hasResumeControl)
        XCTAssertFalse(pending.canPickFan)
        XCTAssertFalse(pending.canResume)
    }
}
