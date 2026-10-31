import Foundation
import XCTest
@testable import HearthKit

final class CpAppGroupRepositoryTests: XCTestCase {
    private func defaults() -> UserDefaults {
        let suite = "cp-owned-import-tests-\(UUID().uuidString)"
        let value = UserDefaults(suiteName: suite)!
        addTeardownBlock { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        return value
    }
    func testImportsCoherentLegacyOnceAndRemovesEverySplitAuthorityKey() throws {
        let defaults = defaults()
        defaults.set(try JSONEncoder().encode(CpStoreFixture.session), forKey: "cpSession")
        defaults.set(try JSONEncoder().encode(CpStoreFixture.location), forKey: "cpLocation")
        defaults.set(CpStoreFixture.runWire, forKey: "cpRun")
        defaults.set(false, forKey: "note_offer")
        defaults.set(CpStoreFixture.udid, forKey: "cpUdid")
        defaults.set(Data("untrusted cached snapshot".utf8), forKey: "cpSnapshot")
        defaults.set("old-scope", forKey: "cpRequestScope")
        defaults.set("old-revision", forKey: "cpActivityRevision")
        defaults.set("retain", forKey: "unrelated-setting")
        let directory = try CpStoreFixture.directory(self)
        let repository = try CpAppGroupRepository(directory: directory, legacyDefaults: defaults, now: CpStoreFixture.now)
        let context = try repository.store.snapshot(now: CpStoreFixture.now)
        XCTAssertEqual(context.session, CpStoreFixture.session)
        XCTAssertEqual(context.location, CpStoreFixture.location)
        XCTAssertEqual(context.run, CpStoreFixture.run)
        XCTAssertFalse(context.alerts.offer)
        XCTAssertEqual(context.udid, CpStoreFixture.udid)
        XCTAssertNil(context.reading)
        XCTAssertNil(context.renderedOrigin?.observationID)
        for key in ["cpSession", "cpLocation", "cpRun", "cpUdid", "cpSnapshot", "cpRequestScope", "cpActivityRevision", "note_offer"] {
            XCTAssertNil(defaults.object(forKey: key))
        }
        XCTAssertEqual(defaults.string(forKey: "unrelated-setting"), "retain")
        defaults.set(try JSONEncoder().encode(CpSession(token: "stale", userId: 99)), forKey: "cpSession")
        let reopened = try CpAppGroupRepository(directory: directory, legacyDefaults: defaults, now: CpStoreFixture.now)
        XCTAssertEqual(try reopened.store.snapshot(now: CpStoreFixture.now).session, context.session)
    }

    func testMarkerAndMissingAuthorityNeverFallBackToLegacyCredentials() throws {
        let directory = try CpStoreFixture.directory(self)
        let defaults = defaults()
        defaults.set(try JSONEncoder().encode(CpStoreFixture.session), forKey: "cpSession")
        try Data("initialized\n".utf8).write(to: directory.appendingPathComponent("cp-state.initialized"))
        XCTAssertThrowsError(try CpAppGroupRepository(directory: directory, legacyDefaults: defaults, now: CpStoreFixture.now))
        XCTAssertNotNil(defaults.data(forKey: "cpSession")) // Do not delete recovery evidence before a durable commit.
    }

    func testLegacyPendingOperationImportsAsUncertainWithoutReplayingOrPublishingOldSnapshot() throws {
        let directory = try CpStoreFixture.directory(self)
        let defaults = defaults()
        defaults.set(try JSONEncoder().encode(CpStoreFixture.session), forKey: "cpSession")
        defaults.set(try JSONEncoder().encode(CpStoreFixture.location), forKey: "cpLocation")
        defaults.set(try JSONEncoder().encode(CpOperation(command: "snooze", startedAt: CpStoreFixture.now)), forKey: "cpOperation")
        let repository = try CpAppGroupRepository(directory: directory, legacyDefaults: defaults, now: CpStoreFixture.now)
        let context = try repository.store.snapshot(now: CpStoreFixture.now)
        XCTAssertEqual(context.operation?.stage, .uncertain)
        XCTAssertEqual(context.operation?.action, .legacy)
        XCTAssertNil(context.renderedOrigin?.observationID)
        XCTAssertTrue(try context.displaySnapshot(now: CpStoreFixture.now).keys.isEmpty)
    }

    func testMalformedLegacyPendingMarkerCannotBeTreatedAsNoOperation() throws {
        let directory = try CpStoreFixture.directory(self)
        let defaults = defaults()
        defaults.set(try JSONEncoder().encode(CpStoreFixture.session), forKey: "cpSession")
        defaults.set(try JSONEncoder().encode(CpStoreFixture.location), forKey: "cpLocation")
        defaults.set(Data("unfinished legacy operation".utf8), forKey: "cpOperation")
        let repository = try CpAppGroupRepository(directory: directory, legacyDefaults: defaults, now: CpStoreFixture.now)
        XCTAssertEqual(try repository.store.snapshot(now: CpStoreFixture.now).operation?.stage, .uncertain)
    }
}
