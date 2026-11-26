import XCTest
@testable import HearthKit

final class ThermostatSelectionTests: XCTestCase {
    private let time = Date(timeIntervalSince1970: 1_800_000_000)
    private let config = HaConfig(baseUrl: "https://example.com", token: "fixture", entityId: "",
        climateId: "climate.room", resumeId: "button.resume", sensorsJson: #"["sensor.a","sensor.b"]"#)

    private func fixture() throws -> (HaStateStore, URL) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return (HaStateStore(directory: directory, initialConfig: config, initialScope: "scope"), directory)
    }

    private func rewrite(_ directory: URL, generation: Any?) throws -> Data {
        let file = directory.appendingPathComponent("ha-state.json")
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any])
        json["thermostatSelectionRevision"] = generation
        let data = try JSONSerialization.data(withJSONObject: json, options: .sortedKeys)
        try data.write(to: file)
        return data
    }

    func testMissingLegacyGenerationMigratesOnceAndIsDurableAcrossReaders() throws {
        let (store, directory) = try fixture()
        _ = try store.snapshot()
        _ = try rewrite(directory, generation: nil)
        let first = try store.snapshot()
        XCTAssertNotNil(first.thermostatSelectionRevision)
        XCTAssertNotNil(first.thermostatSelectionRevision.flatMap(UUID.init(uuidString:)))
        let after = try Data(contentsOf: directory.appendingPathComponent("ha-state.json"))
        let second = try HaStateStore(directory: directory).snapshot()
        XCTAssertEqual(second.thermostatSelectionRevision, first.thermostatSelectionRevision)
        XCTAssertEqual(try Data(contentsOf: directory.appendingPathComponent("ha-state.json")), after)
        XCTAssertEqual(second.config, config)
    }

    func testPresentNullEmptyOrInvalidGenerationIsCorruptionWithoutRecoveryWrite() throws {
        let cases: [Any] = [NSNull(), "", "initial", 1, ["wrong"]]
        for invalid in cases {
            let (store, directory) = try fixture()
            _ = try store.snapshot()
            let bytes = try rewrite(directory, generation: invalid)
            XCTAssertThrowsError(try store.snapshot(), "\(invalid)")
            XCTAssertEqual(try Data(contentsOf: directory.appendingPathComponent("ha-state.json")), bytes)
        }
    }

    func testReadOnlyLegacyProbeStaysUnboundWithoutMigrationWrite() throws {
        let (store, directory) = try fixture()
        _ = try store.snapshot()
        let bytes = try rewrite(directory, generation: nil)
        let context = try HaStateStore(existingProbeDirectory: directory, maximumProbeBytes: 64 * 1024).snapshot()
        XCTAssertNil(context.thermostatSelectionRevision)
        XCTAssertNil(thermostatPresentation(context).origin)
        XCTAssertEqual(try Data(contentsOf: directory.appendingPathComponent("ha-state.json")), bytes)
    }

    func testEverySelectionABARevokesWhileCommandsAndUnrelatedEditsPreserveGeneration() throws {
        let changes: [(inout HaConfig) -> Void] = [
            { $0.climateId = "climate.other" }, { $0.resumeId = "button.other" },
            { $0.sensorsJson = #"["sensor.c","sensor.b"]"# }, { $0.sensorsJson = #"["sensor.b","sensor.a"]"# }
        ]
        for change in changes {
            let (store, _) = try fixture()
            let initial = try store.snapshot()
            var other = config; change(&other)
            _ = try store.saveConfig(other)
            let returned = try store.saveConfig(config)
            XCTAssertNotEqual(returned.thermostatSelectionRevision, initial.thermostatSelectionRevision)
        }
        let (store, _) = try fixture()
        let initial = try store.snapshot()
        var unrelated = config; unrelated.lockName = "Different door"
        let edited = try store.saveConfig(unrelated)
        XCTAssertEqual(edited.thermostatSelectionRevision, initial.thermostatSelectionRevision)
        let started = try XCTUnwrap(store.beginClimateOperation(expectedScope: initial.scope,
            expectedRevision: edited.climateRevision, entityID: config.climateId, action: "heatUp", now: time))
        XCTAssertEqual(started.thermostatSelectionRevision, initial.thermostatSelectionRevision)
        let settled = try XCTUnwrap(store.finishClimateOperation(expectedScope: initial.scope,
            operationID: XCTUnwrap(started.climateOperation).id, error: nil))
        XCTAssertEqual(settled.thermostatSelectionRevision, initial.thermostatSelectionRevision)
        XCTAssertNotEqual(settled.climateRevision, initial.climateRevision)
        XCTAssertNotEqual(try store.replaceConfig(config).thermostatSelectionRevision, initial.thermostatSelectionRevision)
    }

    func testRetiredSelectionRejectsEntireClimateSensorAndFailureBatchWithoutWrite() throws {
        for sensors in [#"["sensor.c","sensor.b"]"#, #"["sensor.b","sensor.a"]"#] {
            let (store, directory) = try fixture()
            let initial = try store.snapshot()
            let old = HaStateReading(entityID: "climate.room", json: #"{"state":"heat"}"#, checkedAt: time)
            let accepted = try XCTUnwrap(store.merge(["climate.room": old], expectedScope: initial.scope,
                failures: ["sensor.a": "old failure"], checkedAt: time))
            var other = config; other.sensorsJson = sensors
            _ = try store.saveConfig(other)
            let returned = try store.saveConfig(config)
            XCTAssertEqual(returned.climateRevision, accepted.climateRevision)
            let before = try Data(contentsOf: directory.appendingPathComponent("ha-state.json"))
            let later = time.addingTimeInterval(60)
            let new = HaStateReading(entityID: "sensor.b", json: #"{"state":"99"}"#, checkedAt: later)
            let newClimate = HaStateReading(entityID: "climate.room", json: #"{"state":"cool"}"#, checkedAt: later)
            let result = try store.merge(["sensor.b": new, "climate.room": newClimate], expectedScope: initial.scope,
                expectedThermostatSelectionRevision: initial.thermostatSelectionRevision,
                failures: ["climate.room": "retired failure", "sensor.a": "new failure"], checkedAt: later)
            XCTAssertNil(result)
            XCTAssertEqual(try Data(contentsOf: directory.appendingPathComponent("ha-state.json")), before)
            let final = try store.snapshot()
            XCTAssertEqual(final.readings, returned.readings)
            XCTAssertEqual(final.failures, returned.failures)
        }
    }

    func testTypedFailuresAndInterruptedOperationsDecodeLegacyConservatively() throws {
        let legacy = #"{"message":"anything","checkedAt":100}"#.data(using: .utf8)!
        XCTAssertEqual(try JSONDecoder().decode(HaStateFailure.self, from: legacy).reason, .other)
        let (store, _) = try fixture()
        let initial = try store.snapshot()
        _ = try store.merge([:], expectedScope: initial.scope, failures: ["climate.room": "no clues"],
            failureReasons: ["climate.room": .authentication], checkedAt: time)
        XCTAssertEqual(try store.snapshot().failures["climate.room"]?.reason, .authentication)
        let started = try XCTUnwrap(store.beginClimateOperation(expectedScope: initial.scope,
            expectedRevision: initial.climateRevision, entityID: config.climateId, action: "heatUp", now: time))
        let expired = try store.expireClimateOperation(now: time.addingTimeInterval(91))
        XCTAssertEqual(expired.climateOperation?.failureKind, .interrupted)
        XCTAssertFalse(try XCTUnwrap(expired.climateOperation).pending)
        XCTAssertEqual(started.thermostatSelectionRevision, expired.thermostatSelectionRevision)
        let oldOperation = #"{"id":"old","entityID":"climate.room","action":"heatUp","startedAt":100,"error":"arbitrary"}"#.data(using: .utf8)!
        XCTAssertEqual(try JSONDecoder().decode(ClimateOperation.self, from: oldOperation).failureKind, .generic)
    }
}
