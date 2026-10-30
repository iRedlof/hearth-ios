import XCTest
@testable import HearthKit

final class HaCollectionStoreTests: XCTestCase {
    private let config = HaConfig(baseUrl: "https://home.example", token: "account-A", entityId: "alarm_control_panel.home",
                                  doorIdsJson: #"["cover.garage"]"#)
    private func store() throws -> HaStateStore {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return HaStateStore(directory: directory, initialConfig: config, initialScope: "scope-A")
    }
    func testFailureRetainsOnlyItsOriginalSuccessfulObservation() throws {
        let store = try store(); let start = try store.snapshot()
        let first = try XCTUnwrap(store.beginCollectionRead("batteries", expectedScope: start.scope, expectedRevision: start.collectionRevision))
        _ = try store.mergeCollection("batteries", reply: .success(#"[{"id":"sensor.a","level":80}]"#),
            expectedScope: start.scope, expectedRevision: start.collectionRevision, readID: first, now: Date(timeIntervalSince1970: 100))
        let next = try XCTUnwrap(store.beginCollectionRead("batteries", expectedScope: start.scope, expectedRevision: start.collectionRevision))
        let result = try XCTUnwrap(store.mergeCollection("batteries", reply: .failure(HaError("Offline")),
            expectedScope: start.scope, expectedRevision: start.collectionRevision, readID: next, now: Date(timeIntervalSince1970: 200)))
        XCTAssertEqual(result.collectionCaches["batteries"]?.observedAt, Date(timeIntervalSince1970: 100))
        XCTAssertEqual(result.collectionCaches["batteries"]?.error, "Offline")
        XCTAssertEqual(result.collectionCaches["batteries"]?.payload, #"[{"id":"sensor.a","level":80}]"#)
    }
    func testOldReadCannotOverwriteNewerRefreshOrReturningSelection() throws {
        let store = try store(); let start = try store.snapshot()
        let older = try XCTUnwrap(store.beginCollectionRead("activity", expectedScope: start.scope, expectedRevision: start.collectionRevision))
        let newer = try XCTUnwrap(store.beginCollectionRead("activity", expectedScope: start.scope, expectedRevision: start.collectionRevision))
        XCTAssertNil(try store.mergeCollection("activity", reply: .success("[]"), expectedScope: start.scope,
            expectedRevision: start.collectionRevision, readID: older, now: Date(timeIntervalSince1970: 100)))
        XCTAssertNotNil(try store.mergeCollection("activity", reply: .success("[]"), expectedScope: start.scope,
            expectedRevision: start.collectionRevision, readID: newer, now: Date(timeIntervalSince1970: 200)))
        var other = config; other.doorIdsJson = #"["cover.other"]"#
        _ = try store.saveConfig(other); let restored = try store.saveConfig(config)
        XCTAssertNotEqual(restored.collectionRevision, start.collectionRevision)
        XCTAssertTrue(restored.collectionCaches.isEmpty)
        XCTAssertNil(try store.mergeCollection("activity", reply: .success("[]"), expectedScope: start.scope,
            expectedRevision: start.collectionRevision, readID: newer))
    }
    func testSelectedEntityReadingCannotLandAfterDoorSelectionChanged() throws {
        let store = try store(); let start = try store.snapshot()
        var other = config; other.doorIdsJson = #"["cover.other"]"#
        _ = try store.saveConfig(other)
        let old = HaStateReading(entityID: "cover.garage", json: #"{"entity_id":"cover.garage","state":"closed"}"#, checkedAt: .now)
        XCTAssertNil(try store.merge([old.entityID: old], expectedScope: start.scope,
            expectedCollectionRevision: start.collectionRevision))
    }
    func testLegacyConfigDecodesAndExplicitEmptySurvivesSave() throws {
        let old = Data(#"{"baseUrl":"https://home.example","token":"fixture","entityId":""}"#.utf8)
        let decoded = try JSONDecoder().decode(HaConfig.self, from: old)
        XCTAssertFalse(decoded.doorsChosen)
        var empty = decoded; empty.doorsChosen = true
        XCTAssertTrue(try JSONDecoder().decode(HaConfig.self, from: JSONEncoder().encode(empty)).doorsChosen)
        XCTAssertEqual(preserveSelectionOrder(["lock.missing", "cover.garage"], selected: ["lock.missing", "binary_sensor.new"],
            available: ["binary_sensor.new", "cover.garage"]), ["lock.missing", "binary_sensor.new"])
    }
    func testDiscoveryAdoptsOnlyTheExactPendingUnchosenContext() throws {
        let store = try store()
        var unchosen = config; unchosen.doorIdsJson = "[]"
        let before = try store.saveConfig(unchosen)
        let readID = try XCTUnwrap(store.beginCollectionRead("doors", expectedScope: before.scope,
            expectedRevision: before.collectionRevision))
        let adopted = try XCTUnwrap(store.adoptDoorDiscovery(["cover.garage"], expectedScope: before.scope,
            expectedRevision: before.collectionRevision, readID: readID))
        XCTAssertEqual(adopted.config?.doorIds, ["cover.garage"])
        XCTAssertEqual(adopted.scope, before.scope)
        XCTAssertNotEqual(adopted.collectionRevision, before.collectionRevision)
        XCTAssertNil(try store.mergeCollection("doors", reply: .success("[]"), expectedScope: before.scope,
            expectedRevision: before.collectionRevision, readID: readID))
        XCTAssertNotNil(try store.mergeCollection("doors", reply: .success("[]"), expectedScope: adopted.scope,
            expectedRevision: adopted.collectionRevision, readID: readID))

        var chosen = unchosen; chosen.doorsChosen = true
        let empty = try store.saveConfig(chosen)
        let next = try XCTUnwrap(store.beginCollectionRead("doors", expectedScope: empty.scope,
            expectedRevision: empty.collectionRevision))
        XCTAssertNil(try store.adoptDoorDiscovery(["cover.garage"], expectedScope: empty.scope,
            expectedRevision: empty.collectionRevision, readID: next))
        XCTAssertEqual(try store.snapshot().config?.doorIds, [])
    }

    func testDoorsReadAcquisitionCannotRaceAnAlreadyStartedCommand() throws {
        let store = try store(), context = try store.snapshot()
        let operation = try XCTUnwrap(store.beginDoorOperation(expectedScope: context.scope,
            expectedRevision: context.doorActionRevision, entityID: "cover.garage", action: "open"))
        XCTAssertNil(try store.beginCollectionRead("doors", expectedScope: context.scope,
            expectedRevision: context.collectionRevision))
        XCTAssertNotNil(try store.beginCollectionRead("activity", expectedScope: context.scope,
            expectedRevision: context.collectionRevision))
        XCTAssertNotNil(try store.beginCollectionRead("batteries", expectedScope: context.scope,
            expectedRevision: context.collectionRevision))
        let command = try XCTUnwrap(operation.doorOperation)
        _ = try store.finishDoorOperation(expectedScope: context.scope, operationID: command.id, error: nil)
        XCTAssertNotNil(try store.beginCollectionRead("doors", expectedScope: context.scope,
            expectedRevision: context.collectionRevision))
    }
}
