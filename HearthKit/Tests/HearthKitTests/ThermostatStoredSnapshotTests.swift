import XCTest
@testable import HearthKit

final class ThermostatStoredSnapshotTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private func store() throws -> HaStateStore {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return HaStateStore(directory: directory,
            initialConfig: HaConfig(baseUrl: "https://example.com", token: "fixture", entityId: "",
                climateId: "climate.room", sensorsJson: #"["sensor.old"]"#),
            initialScope: "scope")
    }
    private func reading(_ value: Int, at date: Date) -> HaStateReading {
        HaStateReading(entityID: "climate.room",
            json: #"{"entity_id":"climate.room","state":"heat","attributes":{"current_temperature":\#(value),"temperature":68,"hvac_modes":["off","heat"]}}"#,
            checkedAt: date)
    }

    func testDisplayReconciliationUsesNewerReadingsWithoutACommandRevisionChange() throws {
        let store = try store()
        let initial = try store.snapshot()
        let first = try XCTUnwrap(store.merge(["climate.room": reading(67, at: now)],
            expectedScope: initial.scope))
        let oldDisplay = thermostatStoredSnapshot(first, now: now)
        let latest = try XCTUnwrap(store.merge(["climate.room": reading(70, at: now.addingTimeInterval(60))],
            expectedScope: initial.scope))
        XCTAssertEqual(first.climateRevision, latest.climateRevision)
        let current = thermostatCurrentFeedback(oldDisplay, context: latest, now: now)
        XCTAssertEqual(current.roomTemp, "70°")
        XCTAssertFalse(current.stale)
    }

    func testDisplayReconciliationShowsPersistedFailureAndCurrentSensorSelection() throws {
        let store = try store()
        let initial = try store.snapshot()
        let first = try XCTUnwrap(store.merge(["climate.room": reading(67, at: now)],
            expectedScope: initial.scope))
        let oldDisplay = thermostatStoredSnapshot(first, now: now)
        var config = try XCTUnwrap(first.config)
        config.sensorsJson = #"["sensor.new"]"#
        _ = try store.saveConfig(config)
        let latest = try XCTUnwrap(store.merge([:], expectedScope: initial.scope,
            failures: ["climate.room": "Can't reach Home Assistant"], checkedAt: now.addingTimeInterval(60)))
        XCTAssertEqual(first.climateRevision, latest.climateRevision)
        let current = thermostatCurrentFeedback(oldDisplay, context: latest, now: now)
        XCTAssertTrue(current.stale)
        XCTAssertEqual(current.roomSub, "Last known")
        XCTAssertEqual(current.status, "Can't connect")
        XCTAssertEqual(current.sensors.map(\.id), ["sensor.new"])
        XCTAssertFalse(current.canAdjustHeatUp)
    }

    func testTransientStorageFailureSurvivesOnlyForItsCurrentBinding() throws {
        let store = try store()
        let context = try store.snapshot()
        var display = thermostatStoredSnapshot(context, now: now,
            transientError: "Can't save readings · Refresh to retry")
        XCTAssertEqual(thermostatCurrentFeedback(display, context: context, now: now).error,
                       "Can't save readings · Refresh to retry")
        display.requestScope = "obsolete"
        XCTAssertNil(thermostatCurrentFeedback(display, context: context, now: now).error)
    }
}
