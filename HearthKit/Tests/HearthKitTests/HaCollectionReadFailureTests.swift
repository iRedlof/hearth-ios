import XCTest
@testable import HearthKit

final class HaCollectionReadFailureTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private func store() throws -> HaStateStore {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return HaStateStore(directory: directory, initialConfig: HaConfig(baseUrl: "https://home.example",
            token: "fixture", entityId: "", doorIdsJson: "[]"), initialScope: "A")
    }

    func testOwnedDiscoveryFailureRemainsAnExplicitFailureBeforeAnyIDsExist() throws {
        let store = try store(), context = try store.snapshot()
        let readID = try XCTUnwrap(store.beginCollectionRead("doors", expectedScope: context.scope,
            expectedRevision: context.collectionRevision))
        let owner = HaCollectionReadOwner(kind: "doors", scope: context.scope, revision: context.collectionRevision, readID: readID)
        let failed = try XCTUnwrap(store.failCollectionRead(owner, error: "Can't connect", now: now))
        XCTAssertEqual(failed.collectionCaches["doors"]?.error, "Can't connect")
        XCTAssertNil(failed.collectionCaches["doors"]?.observedAt)
        let display = mapDoorsSnapshot(config: failed.config, readings: [:], errors: [:], now: now,
            collectionError: failed.collectionCaches["doors"]?.error)
        XCTAssertEqual(display.state, .failed)
        XCTAssertEqual(display.error, "Can't connect")
        XCTAssertTrue(display.doors.isEmpty)
    }

    func testOldAccountFailureCannotAttachToCurrentDoorsBatteriesOrActivity() throws {
        for kind in ["doors", "batteries", "activity"] {
            let store = try store(), old = try store.snapshot()
            let read = try XCTUnwrap(store.beginCollectionRead(kind, expectedScope: old.scope, expectedRevision: old.collectionRevision))
            let owner = HaCollectionReadOwner(kind: kind, scope: old.scope, revision: old.collectionRevision, readID: read)
            var config = try XCTUnwrap(old.config); config.token = "account-B"
            let current = try store.saveConfig(config)
            let currentRead = try XCTUnwrap(store.beginCollectionRead(kind, expectedScope: current.scope,
                expectedRevision: current.collectionRevision))
            _ = try store.mergeCollection(kind, reply: .success("current-success"), expectedScope: current.scope,
                expectedRevision: current.collectionRevision, readID: currentRead, now: now)
            XCTAssertNil(try store.failCollectionRead(owner, error: "OLD sign-in failure", now: now.addingTimeInterval(1)))
            let visible = try store.snapshot()
            XCTAssertEqual(visible.collectionCaches[kind]?.payload, "current-success")
            XCTAssertNil(visible.collectionCaches[kind]?.error)
        }
    }

    func testOlderSameSelectionFailureCannotSettleANewerReadOrSuccessfulCompletion() throws {
        for kind in ["doors", "batteries", "activity"] {
            let store = try store(), context = try store.snapshot()
            let old = try XCTUnwrap(store.beginCollectionRead(kind, expectedScope: context.scope, expectedRevision: context.collectionRevision))
            let owner = HaCollectionReadOwner(kind: kind, scope: context.scope, revision: context.collectionRevision, readID: old)
            let new = try XCTUnwrap(store.beginCollectionRead(kind, expectedScope: context.scope, expectedRevision: context.collectionRevision))
            XCTAssertNil(try store.failCollectionRead(owner, error: "OLD failure", now: now))
            XCTAssertNotNil(try store.mergeCollection(kind, reply: .success("new-success"), expectedScope: context.scope,
                expectedRevision: context.collectionRevision, readID: new, now: now))
            XCTAssertNil(try store.failCollectionRead(owner, error: "OLD failure", now: now.addingTimeInterval(1)))
            XCTAssertNil(try store.snapshot().collectionCaches[kind]?.error)
        }
    }
}
