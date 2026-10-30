import XCTest
@testable import HearthKit

final class HaSettingsEditTests: XCTestCase {
    private let config = HaConfig(baseUrl: "https://home.example", token: "account-A", entityId: "")
    private func store() throws -> HaStateStore {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return HaStateStore(directory: directory, initialConfig: config, initialScope: "scope-A")
    }

    func testPreferenceEditPreservesDoorsAdoptedAfterSettingsOpened() throws {
        let store = try store(), opened = try store.snapshot()
        let discovery = try XCTUnwrap(store.beginCollectionRead("doors", expectedScope: opened.scope,
            expectedRevision: opened.collectionRevision))
        let adopted = try XCTUnwrap(store.adoptDoorDiscovery(["cover.garage", "cover.gate"],
            expectedScope: opened.scope, expectedRevision: opened.collectionRevision, readID: discovery))
        let read = try XCTUnwrap(store.beginCollectionRead("batteries", expectedScope: adopted.scope,
            expectedRevision: adopted.collectionRevision))
        _ = try store.mergeCollection("batteries", reply: .success("[]"), expectedScope: adopted.scope,
            expectedRevision: adopted.collectionRevision, readID: read, now: Date(timeIntervalSince1970: 100))

        let edited = try XCTUnwrap(store.editConfig(expectedScope: opened.scope) { $0.confirmWith = CONFIRM_DIALOG })
        XCTAssertEqual(edited.config?.doorIds, ["cover.garage", "cover.gate"])
        XCTAssertEqual(edited.config?.confirmWith, CONFIRM_DIALOG)
        XCTAssertEqual(edited.collectionRevision, adopted.collectionRevision)
        XCTAssertEqual(edited.collectionCaches["batteries"]?.observedAt, Date(timeIntervalSince1970: 100))
        XCTAssertEqual(try store.snapshot().config?.doorIds, ["cover.garage", "cover.gate"])
    }

    func testDoorSelectionEditRevokesOldReadsAndCaches() throws {
        let store = try store(), context = try store.snapshot()
        let read = try XCTUnwrap(store.beginCollectionRead("batteries", expectedScope: context.scope,
            expectedRevision: context.collectionRevision))
        _ = try store.mergeCollection("batteries", reply: .success("[]"), expectedScope: context.scope,
            expectedRevision: context.collectionRevision, readID: read)
        let oldDoorsRead = try XCTUnwrap(store.beginCollectionRead("doors", expectedScope: context.scope,
            expectedRevision: context.collectionRevision))

        let edited = try XCTUnwrap(store.editConfig(expectedScope: context.scope) {
            $0.doorIdsJson = #"["cover.gate"]"#
            $0.doorsChosen = true
        })
        XCTAssertEqual(edited.config?.doorIds, ["cover.gate"])
        XCTAssertTrue(edited.config?.doorsChosen == true)
        XCTAssertNotEqual(edited.collectionRevision, context.collectionRevision)
        XCTAssertTrue(edited.collectionCaches.isEmpty)
        XCTAssertNil(try store.mergeCollection("doors", reply: .success("[]"),
            expectedScope: context.scope, expectedRevision: context.collectionRevision, readID: oldDoorsRead))
    }

    func testSettingsFromAnOlderAccountCannotEditAfterReturningToThatAccount() throws {
        let store = try store(), opened = try store.snapshot()
        var other = config
        other.token = "account-B"
        _ = try store.saveConfig(other)
        let current = try store.saveConfig(config)
        var called = false
        XCTAssertNil(try store.editConfig(expectedScope: opened.scope) {
            called = true
            $0.lockId = "lock.old_account"
        })
        XCTAssertFalse(called)
        let preserved = try store.snapshot()
        XCTAssertEqual(preserved.scope, current.scope)
        XCTAssertEqual(preserved.config?.lockId, "")
    }

    func testSignedOutSettingsCannotCreateAConfiguration() throws {
        let store = try store(), signedOut = try store.replaceConfig(nil)
        var called = false
        XCTAssertNil(try store.editConfig(expectedScope: signedOut.scope) { _ in called = true })
        XCTAssertFalse(called)
        XCTAssertNil(try store.snapshot().config)
    }
}
