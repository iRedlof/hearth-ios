import XCTest
@testable import HearthKit

final class HaStateStoreTests: XCTestCase {
    private let config = HaConfig(baseUrl: "https://example.com", token: "fixture", entityId: "",
                                  climateId: "climate.room")
    private func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }
    private func reading(_ id: String, at: TimeInterval) -> HaStateReading {
        HaStateReading(entityID: id, json: #"{"entity_id":"\#(id)","state":"on"}"#,
                       checkedAt: Date(timeIntervalSince1970: at))
    }

    func testConfigAndScopeAreOnePersistentContext() throws {
        let dir = try directory()
        let first = HaStateStore(directory: dir, initialConfig: config, initialScope: "migrated")
        let initial = try first.snapshot()
        XCTAssertEqual(initial.config, config)
        XCTAssertEqual(initial.scope, "migrated")
        let second = HaStateStore(directory: dir)
        var selected = config; selected.climateId = "climate.other"
        let saved = try second.saveConfig(selected)
        XCTAssertEqual(saved.config?.climateId, "climate.other")
        XCTAssertEqual(saved.scope, "migrated")
        XCTAssertEqual(try first.snapshot().config?.climateId, "climate.other")
    }

    func testOldScopeCannotRestoreReadingsAfterSignOutOrSameAccountSignIn() throws {
        let store = HaStateStore(directory: try directory(), initialConfig: config, initialScope: "old")
        _ = try store.snapshot()
        XCTAssertNotNil(try store.merge(["climate.room": reading("climate.room", at: 1)], expectedScope: "old"))
        let signedOut = try store.saveConfig(nil)
        XCTAssertNotEqual(signedOut.scope, "old")
        XCTAssertNil(signedOut.config)
        XCTAssertTrue(signedOut.readings.isEmpty)
        XCTAssertNil(try store.merge(["climate.room": reading("climate.room", at: 2)], expectedScope: "old"))
        let signedIn = try store.saveConfig(config)
        XCTAssertNotEqual(signedIn.scope, "old")
        XCTAssertNil(try store.merge(["climate.room": reading("climate.room", at: 3)], expectedScope: "old"))
        XCTAssertTrue(try store.snapshot().readings.isEmpty)
    }

    func testPerEntityMergeKeepsNewestSuccessfulReadAndRejectsWrongIdentity() throws {
        let store = HaStateStore(directory: try directory(), initialConfig: config, initialScope: "scope")
        _ = try store.snapshot()
        _ = try store.merge(["sensor.a": reading("sensor.a", at: 10)], expectedScope: "scope")
        let merged = try XCTUnwrap(store.merge([
            "sensor.a": reading("sensor.a", at: 5),
            "sensor.b": reading("sensor.b", at: 6),
            "sensor.c": reading("sensor.wrong", at: 9)
        ], expectedScope: "scope"))
        XCTAssertEqual(merged.readings["sensor.a"]?.checkedAt, Date(timeIntervalSince1970: 10))
        XCTAssertEqual(merged.readings["sensor.b"]?.checkedAt, Date(timeIntervalSince1970: 6))
        XCTAssertNil(merged.readings["sensor.c"])
    }

    func testIndependentInstancesCannotLoseConcurrentEntityUpdates() throws {
        let dir = try directory()
        let store = HaStateStore(directory: dir, initialConfig: config, initialScope: "scope")
        _ = try store.snapshot()
        let failures = StoreFailures()
        DispatchQueue.concurrentPerform(iterations: 64) { index in
            do {
                let id = "sensor.\(index)"
                let reading = HaStateReading(entityID: id, json: #"{"state":"on"}"#,
                    checkedAt: Date(timeIntervalSince1970: Double(index)))
                _ = try HaStateStore(directory: dir).merge([id: reading], expectedScope: "scope")
            } catch { failures.append(String(describing: error)) }
        }
        XCTAssertTrue(failures.values.isEmpty, "\(failures.values)")
        XCTAssertEqual(try store.snapshot().readings.count, 64)
    }

    func testMalformedFileCannotResetIdentityOrOverwriteAuthoritativeData() throws {
        let dir = try directory()
        let store = HaStateStore(directory: dir, initialConfig: config, initialScope: "scope")
        _ = try store.snapshot()
        let file = dir.appendingPathComponent("ha-state.json")
        let corrupt = Data("not json".utf8)
        try corrupt.write(to: file)
        XCTAssertThrowsError(try store.snapshot())
        XCTAssertThrowsError(try store.saveConfig(nil))
        XCTAssertThrowsError(try store.merge([:], expectedScope: "scope"))
        XCTAssertEqual(try Data(contentsOf: file), corrupt)
    }

    func testExplicitRecoveryRotatesIdentityAndRejectsOldWriters() throws {
        let dir = try directory()
        let store = HaStateStore(directory: dir, initialConfig: config, initialScope: "old")
        _ = try store.snapshot()
        try Data("corrupt".utf8).write(to: dir.appendingPathComponent("ha-state.json"))
        let recovered = try store.replaceConfig(nil)
        XCTAssertNil(recovered.config)
        XCTAssertNotEqual(recovered.scope, "old")
        XCTAssertTrue(recovered.readings.isEmpty)
        XCTAssertNil(try store.merge(["sensor.a": reading("sensor.a", at: 10)], expectedScope: "old"))
        XCTAssertNil(try store.snapshot().config)
    }
}

private final class StoreFailures: @unchecked Sendable {
    private let lock = NSLock()
    private var messages: [String] = []
    func append(_ value: String) { lock.lock(); defer { lock.unlock() }; messages.append(value) }
    var values: [String] { lock.lock(); defer { lock.unlock() }; return messages }
}
