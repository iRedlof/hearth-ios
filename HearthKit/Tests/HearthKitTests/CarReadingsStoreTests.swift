import XCTest
@testable import HearthKit

final class CarReadingsStoreTests: XCTestCase {
    private let config = HaConfig(baseUrl: "https://home.example", token: "fixture", entityId: "")
    private let first = Date(timeIntervalSince1970: 1_800_000_000)

    private func store() throws -> HaStateStore {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return HaStateStore(directory: directory, initialConfig: config, initialScope: "account-A")
    }

    private static func reply(_ battery: String, prefix: String = "stargate") -> String {
        """
        {"found":true,"prefix":"\(prefix)","name":"Same name","s":{
        "sensor.battery_level":"\(battery)","sensor.charging":"charging","sensor.charger_power":"7.25"}}
        """
    }

    // Car must acquire a real owned read, rather than check-and-set a separate defaults record.
    func testSuccessfulCarReplyIsAnOwnedAtomicCacheRecord() throws {
        let store = try store(), start = try store.snapshot()
        let read = try XCTUnwrap(store.beginCollectionRead("car", expectedScope: start.scope,
            expectedRevision: start.scope, now: first))
        let stored = try XCTUnwrap(store.mergeCollection("car", reply: .success(Self.reply("84")),
            expectedScope: start.scope, expectedRevision: start.scope, readID: read, now: first))
        let payload = try XCTUnwrap(stored.collectionCaches["car"]?.payload)
        let cache = try JSONDecoder().decode(CarReadingsCache.self, from: Data(payload.utf8))
        XCTAssertEqual(cache.current, Self.reply("84"))
        XCTAssertEqual(cache.lastGood, Self.reply("84"))
        XCTAssertEqual(cache.checkedAt, first)
        XCTAssertEqual(stored.collectionCaches["car"]?.observedAt, first)
        XCTAssertNil(try store.mergeCollection("car", reply: .success(Self.reply("20")),
            expectedScope: start.scope, expectedRevision: start.scope, readID: read,
            now: first.addingTimeInterval(60)))
    }

    // The committed reply must reconcile history under the same lock as the latest successful cache.
    func testSameVehicleUnknownReplyRetainsCommittedHistory() throws {
        let store = try store(), start = try store.snapshot()
        let firstRead = try XCTUnwrap(store.beginCollectionRead("car", expectedScope: start.scope,
            expectedRevision: start.scope, now: first))
        _ = try store.mergeCollection("car", reply: .success(Self.reply("84")),
            expectedScope: start.scope, expectedRevision: start.scope, readID: firstRead, now: first)
        let read = try XCTUnwrap(store.beginCollectionRead("car", expectedScope: start.scope,
            expectedRevision: start.scope, now: first.addingTimeInterval(60)))
        let stored = try XCTUnwrap(store.mergeCollection("car", reply: .success(Self.reply("unknown")),
            expectedScope: start.scope, expectedRevision: start.scope, readID: read,
            now: first.addingTimeInterval(60)))
        let payload = try XCTUnwrap(stored.collectionCaches["car"]?.payload)
        let cache = try JSONDecoder().decode(CarReadingsCache.self, from: Data(payload.utf8))
        XCTAssertEqual(CarFetchResult(cache: cache).snapshot(now: first).battery, 84)
        XCTAssertEqual(cache.lastGood, Self.reply("84"))
        XCTAssertEqual(cache.checkedAt, first.addingTimeInterval(60))
    }

    // An older in-flight result cannot overwrite a newly acquired read, regardless of completion order.
    func testOverlappingOlderCarReplyCannotReplaceNewerRead() throws {
        let store = try store(), start = try store.snapshot()
        let old = try XCTUnwrap(store.beginCollectionRead("car", expectedScope: start.scope,
            expectedRevision: start.scope, now: first))
        let newer = try XCTUnwrap(store.beginCollectionRead("car", expectedScope: start.scope,
            expectedRevision: start.scope, now: first.addingTimeInterval(1)))
        XCTAssertNil(try store.mergeCollection("car", reply: .success(Self.reply("84")),
            expectedScope: start.scope, expectedRevision: start.scope, readID: old, now: first))
        let stored = try XCTUnwrap(store.mergeCollection("car", reply: .success(Self.reply("unknown")),
            expectedScope: start.scope, expectedRevision: start.scope, readID: newer,
            now: first.addingTimeInterval(60)))
        let payload = try XCTUnwrap(stored.collectionCaches["car"]?.payload)
        let cache = try JSONDecoder().decode(CarReadingsCache.self, from: Data(payload.utf8))
        XCTAssertNil(cache.lastGood)
        XCTAssertNil(CarFetchResult(cache: cache).snapshot(now: first).battery)
    }

    // A scope that returned to the same credentials is still a new account generation.
    func testAccountReplacementRevokesCarReplyEvenWhenCredentialsReturn() throws {
        let store = try store(), start = try store.snapshot()
        let read = try XCTUnwrap(store.beginCollectionRead("car", expectedScope: start.scope,
            expectedRevision: start.scope, now: first))
        _ = try store.saveConfig(nil)
        let restored = try store.saveConfig(config)
        XCTAssertNil(try store.mergeCollection("car", reply: .success(Self.reply("84")),
            expectedScope: start.scope, expectedRevision: start.scope, readID: read, now: first))
        XCTAssertNotEqual(restored.scope, start.scope)
        XCTAssertTrue(try store.snapshot().collectionCaches.isEmpty)
    }

    // A failure retains telemetry with its actual successful time and never restamps it as fresh.
    func testCarFailureKeepsCommittedPayloadAndOriginalObservation() throws {
        let store = try store(), start = try store.snapshot()
        let read = try XCTUnwrap(store.beginCollectionRead("car", expectedScope: start.scope,
            expectedRevision: start.scope, now: first))
        let good = try XCTUnwrap(store.mergeCollection("car", reply: .success(Self.reply("84")),
            expectedScope: start.scope, expectedRevision: start.scope, readID: read, now: first))
        let next = try XCTUnwrap(store.beginCollectionRead("car", expectedScope: start.scope,
            expectedRevision: start.scope, now: first.addingTimeInterval(60)))
        let failed = try XCTUnwrap(store.mergeCollection("car", reply: .failure(HaError("Offline")),
            expectedScope: start.scope, expectedRevision: start.scope, readID: next,
            now: first.addingTimeInterval(60)))
        XCTAssertEqual(failed.collectionCaches["car"]?.payload, good.collectionCaches["car"]?.payload)
        XCTAssertEqual(failed.collectionCaches["car"]?.observedAt, first)
        XCTAssertEqual(failed.collectionCaches["car"]?.attemptedAt, first.addingTimeInterval(60))
        XCTAssertEqual(failed.collectionCaches["car"]?.error, "Offline")
    }

    // Parsing failure cannot replace a valid cache or leave an endlessly reusable read owner.
    func testMalformedCarReplySettlesAsFailureWithoutReplacingTelemetry() throws {
        let store = try store(), start = try store.snapshot()
        let read = try XCTUnwrap(store.beginCollectionRead("car", expectedScope: start.scope,
            expectedRevision: start.scope, now: first))
        let good = try XCTUnwrap(store.mergeCollection("car", reply: .success(Self.reply("84")),
            expectedScope: start.scope, expectedRevision: start.scope, readID: read, now: first))
        let next = try XCTUnwrap(store.beginCollectionRead("car", expectedScope: start.scope,
            expectedRevision: start.scope, now: first.addingTimeInterval(60)))
        let failed = try XCTUnwrap(store.mergeCollection("car", reply: .success(#"{"found":true}"#),
            expectedScope: start.scope, expectedRevision: start.scope, readID: next,
            now: first.addingTimeInterval(60)))
        XCTAssertEqual(failed.collectionCaches["car"]?.payload, good.collectionCaches["car"]?.payload)
        XCTAssertEqual(failed.collectionCaches["car"]?.observedAt, first)
        XCTAssertEqual(failed.collectionCaches["car"]?.error, "Couldn't read car data")
        XCTAssertNil(try store.mergeCollection("car", reply: .success(Self.reply("20")),
            expectedScope: start.scope, expectedRevision: start.scope, readID: next,
            now: first.addingTimeInterval(120)))
    }

    // Car discovery belongs to the account; an alarm/door picker edit must not erase sleeping-car history.
    func testUnrelatedPickerEditPreservesCarCache() throws {
        let store = try store(), start = try store.snapshot()
        let read = try XCTUnwrap(store.beginCollectionRead("car", expectedScope: start.scope,
            expectedRevision: start.scope, now: first))
        let good = try XCTUnwrap(store.mergeCollection("car", reply: .success(Self.reply("84")),
            expectedScope: start.scope, expectedRevision: start.scope, readID: read, now: first))
        var edited = config
        edited.entityId = "alarm_control_panel.other"
        edited.lockId = "lock.front_door"
        edited.doorIdsJson = #"["cover.garage"]"#
        let after = try store.saveConfig(edited)
        XCTAssertEqual(after.scope, start.scope)
        XCTAssertNotEqual(after.collectionRevision, start.collectionRevision)
        XCTAssertEqual(after.collectionCaches["car"]?.payload, good.collectionCaches["car"]?.payload)
        XCTAssertEqual(after.collectionCaches["car"]?.observedAt, first)
    }

    // Harmless same-account selection changes cannot revoke an already captured Car network response.
    func testUnrelatedPickerEditPreservesInFlightCarReadOwnership() throws {
        let store = try store(), start = try store.snapshot()
        let read = try XCTUnwrap(store.beginCollectionRead("car", expectedScope: start.scope,
            expectedRevision: start.scope, now: first))
        var edited = config
        edited.entityId = "alarm_control_panel.other"
        edited.doorIdsJson = #"["cover.garage"]"#
        _ = try store.saveConfig(edited)
        let result = try store.mergeCollection("car", reply: .success(Self.reply("84")),
            expectedScope: start.scope, expectedRevision: start.scope, readID: read, now: first)
        XCTAssertNotNil(result)
        XCTAssertNotNil(try store.snapshot().collectionCaches["car"]?.payload)
    }

    // Automatic Door discovery is another unrelated selection edit and must preserve Car ownership.
    func testDoorDiscoveryKeepsCarHistoryAndInFlightRefresh() throws {
        let store = try store(), start = try store.snapshot()
        let firstRead = try XCTUnwrap(store.beginCollectionRead("car", expectedScope: start.scope,
            expectedRevision: start.scope, now: first))
        let good = try XCTUnwrap(store.mergeCollection("car", reply: .success(Self.reply("84")),
            expectedScope: start.scope, expectedRevision: start.scope, readID: firstRead, now: first))
        let carRead = try XCTUnwrap(store.beginCollectionRead("car", expectedScope: start.scope,
            expectedRevision: start.scope, now: first.addingTimeInterval(60)))
        let doorRead = try XCTUnwrap(store.beginCollectionRead("doors", expectedScope: start.scope,
            expectedRevision: start.collectionRevision))
        let adopted = try XCTUnwrap(store.adoptDoorDiscovery(["cover.garage"], expectedScope: start.scope,
            expectedRevision: start.collectionRevision, readID: doorRead))
        XCTAssertEqual(adopted.collectionCaches["car"]?.payload, good.collectionCaches["car"]?.payload)
        let after = try XCTUnwrap(store.mergeCollection("car", reply: .success(Self.reply("unknown")),
            expectedScope: start.scope, expectedRevision: start.scope, readID: carRead,
            now: first.addingTimeInterval(60)))
        let payload = try XCTUnwrap(after.collectionCaches["car"]?.payload)
        let cache = try JSONDecoder().decode(CarReadingsCache.self, from: Data(payload.utf8))
        XCTAssertEqual(CarFetchResult(cache: cache).snapshot(now: first).battery, 84)
    }
}
