import Foundation
import XCTest
@testable import HearthKit

final class CpStateStoreMigrationTests: XCTestCase {
    func testBootstrapImportsOnceAndCannotResurrectLegacyCredentialsAfterSignOut() throws {
        let directory = try CpStoreFixture.directory(self)
        let store = CpStateStore(directory: directory)
        let imported = try store.bootstrap(legacy: CpStoreFixture.legacy, now: CpStoreFixture.now)
        let signedOut = try XCTUnwrap(store.edit(expected: imported.settingsOrigin, edit: .signOut,
                                                now: CpStoreFixture.now))
        let reopened = try CpStateStore(directory: directory).bootstrap(legacy: CpStoreFixture.legacy,
                                                                       now: CpStoreFixture.now)
        XCTAssertEqual(reopened, signedOut)
        XCTAssertEqual(reopened.session, CpSession())
        XCTAssertEqual(reopened.run, CpRun())
        XCTAssertNil(reopened.location)
        XCTAssertEqual(reopened.alerts, CpStoreFixture.alerts)
        XCTAssertEqual(reopened.udid, CpStoreFixture.udid)
        XCTAssertNil(reopened.reading)
        XCTAssertNil(reopened.activeRead)
    }

    func testMalformedLegacyRunCannotArmAnImportedSession() throws {
        let store = CpStateStore(directory: try CpStoreFixture.directory(self))
        let legacy = CpLegacyState(session: CpStoreFixture.session, location: CpStoreFixture.location,
                                   runWire: "1|bogus", alerts: CpStoreFixture.alerts, udid: CpStoreFixture.udid)
        let saved = try store.bootstrap(legacy: legacy, now: CpStoreFixture.now)
        XCTAssertEqual(saved.session, CpStoreFixture.session)
        XCTAssertEqual(saved.run, CpRun())
        XCTAssertEqual(saved.alerts, CpStoreFixture.alerts)
    }

    func testUnsignedLegacyStateCannotImportAnArmedRunOrLocation() throws {
        let store = CpStateStore(directory: try CpStoreFixture.directory(self))
        let legacy = CpLegacyState(session: CpSession(), location: CpStoreFixture.location,
                                   runWire: CpStoreFixture.runWire, alerts: CpStoreFixture.alerts,
                                   udid: CpStoreFixture.udid)
        let saved = try store.bootstrap(legacy: legacy, now: CpStoreFixture.now)
        XCTAssertEqual(saved.session, CpSession())
        XCTAssertNil(saved.location)
        XCTAssertEqual(saved.run, CpRun())
        XCTAssertEqual(saved.alerts, CpStoreFixture.alerts)
        XCTAssertEqual(saved.udid, CpStoreFixture.udid)
    }

    func testMissingFileAfterInitializationCannotReimportLegacyCredentials() throws {
        let directory = try CpStoreFixture.directory(self)
        let store = CpStateStore(directory: directory)
        _ = try store.bootstrap(legacy: CpStoreFixture.legacy, now: CpStoreFixture.now)
        try FileManager.default.removeItem(at: directory.appendingPathComponent("cp-state.json"))
        XCTAssertThrowsError(try store.bootstrap(legacy: CpStoreFixture.legacy, now: CpStoreFixture.now))
        XCTAssertThrowsError(try store.snapshot(now: CpStoreFixture.now))
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent("cp-state.json").path))
    }

    func testInitializedMarkerWithoutJSONFailsClosedThenExplicitRecoveryStaysSignedOut() throws {
        let directory = try CpStoreFixture.directory(self)
        try Data("initialized".utf8).write(to: directory.appendingPathComponent("cp-state.initialized"))
        let store = CpStateStore(directory: directory)
        XCTAssertThrowsError(try store.bootstrap(legacy: CpStoreFixture.legacy, now: CpStoreFixture.now))
        let recovered = try store.recoverSignedOut(now: CpStoreFixture.now)
        XCTAssertEqual(recovered.session, CpSession())
        XCTAssertEqual(recovered.run, CpRun())
        XCTAssertNil(recovered.location)
        let reopened = try store.bootstrap(legacy: CpStoreFixture.legacy, now: CpStoreFixture.now)
        XCTAssertEqual(reopened, recovered)
    }

    func testCorruptionIsNotOverwrittenByOrdinaryReadBootstrapOrEdit() throws {
        let directory = try CpStoreFixture.directory(self)
        let store = CpStateStore(directory: directory)
        let before = try store.bootstrap(legacy: CpStoreFixture.legacy, now: CpStoreFixture.now)
        let path = directory.appendingPathComponent("cp-state.json")
        let corrupt = Data("invalid authoritative JSON".utf8)
        try corrupt.write(to: path)
        XCTAssertThrowsError(try store.snapshot(now: CpStoreFixture.now))
        XCTAssertThrowsError(try store.bootstrap(legacy: CpStoreFixture.legacy, now: CpStoreFixture.now))
        XCTAssertThrowsError(try store.edit(expected: before.settingsOrigin, edit: .signOut, now: CpStoreFixture.now))
        XCTAssertEqual(try Data(contentsOf: path), corrupt)
        let recovered = try store.recoverSignedOut(now: CpStoreFixture.now)
        XCTAssertEqual(recovered.session, CpSession())
        XCTAssertNotEqual(recovered.context.accountGeneration, before.context.accountGeneration)
        XCTAssertNil(try store.edit(expected: before.settingsOrigin, edit: .location(CpStoreFixture.location),
                                    now: CpStoreFixture.now))
    }

    func testUnsupportedSchemaIsNotSilentlyDowngradedOrReimported() throws {
        let directory = try CpStoreFixture.directory(self)
        let store = CpStateStore(directory: directory)
        _ = try store.bootstrap(legacy: CpStoreFixture.legacy, now: CpStoreFixture.now)
        let path = directory.appendingPathComponent("cp-state.json")
        let bytes = Data(#"{"version":999}"#.utf8)
        try bytes.write(to: path)
        XCTAssertThrowsError(try store.snapshot(now: CpStoreFixture.now))
        XCTAssertThrowsError(try store.bootstrap(legacy: CpStoreFixture.legacy, now: CpStoreFixture.now))
        XCTAssertEqual(try Data(contentsOf: path), bytes)
    }

    func testUncommittedStagedFileCannotReplaceTheAuthoritativeRecord() throws {
        let directory = try CpStoreFixture.directory(self)
        let store = CpStateStore(directory: directory)
        let before = try store.bootstrap(legacy: CpStoreFixture.legacy, now: CpStoreFixture.now)
        try Data("interrupted staged write".utf8)
            .write(to: directory.appendingPathComponent(".cp-state-abandoned.json"))
        XCTAssertEqual(try CpStateStore(directory: directory).snapshot(now: CpStoreFixture.now), before)
    }

    func testStoreFilesAndDirectoryHavePrivatePermissions() throws {
        let directory = try CpStoreFixture.directory(self)
        let store = CpStateStore(directory: directory)
        _ = try store.bootstrap(legacy: CpStoreFixture.legacy, now: CpStoreFixture.now)
        for name in ["cp-state.json", "cp-state.lock", "cp-state.initialized"] {
            let attributes = try FileManager.default.attributesOfItem(atPath: directory.appendingPathComponent(name).path)
            XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o600, name)
        }
        let attributes = try FileManager.default.attributesOfItem(atPath: directory.path)
        XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o700)
    }

    func testUnavailableDirectoryDoesNotCreateAnAlternateFallbackRecord() throws {
        let parent = try CpStoreFixture.directory(self)
        let blocked = parent.appendingPathComponent("blocked")
        let bytes = Data("ordinary file".utf8)
        try bytes.write(to: blocked)
        let store = CpStateStore(directory: blocked)
        XCTAssertThrowsError(try store.bootstrap(legacy: CpStoreFixture.legacy, now: CpStoreFixture.now))
        XCTAssertThrowsError(try store.snapshot(now: CpStoreFixture.now))
        XCTAssertEqual(try Data(contentsOf: blocked), bytes)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: parent.path), ["blocked"])
    }

    func testLegacyArmedRunWithoutLocationImportsPausedHistory() throws {
        let directory = try CpStoreFixture.directory(self)
        let store = CpStateStore(directory: directory)
        let legacy = CpLegacyState(session: CpStoreFixture.session, location: nil,
            runWire: CpStoreFixture.runWire, alerts: CpStoreFixture.alerts, udid: CpStoreFixture.udid)
        let saved = try store.bootstrap(legacy: legacy, now: CpStoreFixture.now)
        XCTAssertEqual(saved.session, CpStoreFixture.session)
        XCTAssertNil(saved.location)
        XCTAssertEqual(saved.run, cpPauseRun(CpStoreFixture.run))
        XCTAssertEqual(saved.alerts, CpStoreFixture.alerts)
        XCTAssertEqual(saved.udid, CpStoreFixture.udid)
        XCTAssertEqual(try CpStateStore(directory: directory).snapshot(now: CpStoreFixture.now), saved)
    }

    func testLegacyArmedRunWithInvalidLocationImportsPausedHistory() throws {
        let directory = try CpStoreFixture.directory(self)
        let store = CpStateStore(directory: directory)
        let invalid = CpLocation(name: "Invalid fixture", address: "Fixture",
            deviceIds: [], bounds: CpBounds(swLat: 0, swLon: 0, neLat: 1, neLon: 1))
        let legacy = CpLegacyState(session: CpStoreFixture.session, location: invalid,
            runWire: CpStoreFixture.runWire, alerts: CpStoreFixture.alerts, udid: CpStoreFixture.udid)
        let saved = try store.bootstrap(legacy: legacy, now: CpStoreFixture.now)
        XCTAssertEqual(saved.session, CpStoreFixture.session)
        XCTAssertNil(saved.location)
        XCTAssertEqual(saved.run, cpPauseRun(CpStoreFixture.run))
        XCTAssertEqual(saved.alerts, CpStoreFixture.alerts)
        XCTAssertEqual(saved.udid, CpStoreFixture.udid)
        XCTAssertEqual(try CpStateStore(directory: directory).snapshot(now: CpStoreFixture.now), saved)
    }

    func testAuthoritativeArmedRunWithoutSelectionFailsClosed() throws {
        let directory = try CpStoreFixture.directory(self)
        let store = CpStateStore(directory: directory)
        let before = try store.bootstrap(legacy: CpStoreFixture.legacy, now: CpStoreFixture.now)
        let path = directory.appendingPathComponent("cp-state.json")
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: path)) as? [String: Any])
        object.removeValue(forKey: "location")
        let corrupt = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        try corrupt.write(to: path)
        for operation in [
            { _ = try store.snapshot(now: CpStoreFixture.now) },
            { _ = try store.beginRead(expected: before.context, now: CpStoreFixture.now) },
            { _ = try store.edit(expected: before.settingsOrigin, edit: .pause, now: CpStoreFixture.now) }
        ] {
            XCTAssertThrowsError(try operation()) { XCTAssertEqual($0 as? CpStateStoreError, .corrupt) }
            XCTAssertEqual(try Data(contentsOf: path), corrupt)
        }
        let recovered = try store.recoverSignedOut(now: CpStoreFixture.now)
        XCTAssertEqual(recovered.session, CpSession())
        XCTAssertNil(recovered.location)
        XCTAssertEqual(recovered.run, CpRun())
    }

    func testOldPresentationReadingSchemaDoesNotReimportOrNormalize() throws {
        let directory = try CpStoreFixture.directory(self)
        let store = CpStateStore(directory: directory)
        _ = try store.bootstrap(legacy: CpStoreFixture.legacy, now: CpStoreFixture.now)
        let path = directory.appendingPathComponent("cp-state.json")
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: path)) as? [String: Any])
        object["version"] = 1
        let oldSnapshot = CpSnapshot(site: "Old office", account: "old account", bigAnswer: "Your turn",
            unit: "to accept", sub: "Old caption", plugsFree: nil, autoOn: true, actionLabel: "Open",
            autoControl: .stop)
        object["reading"] = ["snapshot": try JSONSerialization.jsonObject(with: JSONEncoder().encode(oldSnapshot)),
                             "observedAt": CpStoreFixture.now.timeIntervalSinceReferenceDate]
        let oldBytes = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        try oldBytes.write(to: path)
        XCTAssertThrowsError(try store.snapshot(now: CpStoreFixture.now)) {
            XCTAssertEqual($0 as? CpStateStoreError, .unsupportedVersion)
        }
        XCTAssertThrowsError(try store.bootstrap(legacy: CpStoreFixture.legacy, now: CpStoreFixture.now)) {
            XCTAssertEqual($0 as? CpStateStoreError, .unsupportedVersion)
        }
        XCTAssertEqual(try Data(contentsOf: path), oldBytes)
        XCTAssertTrue(FileManager.default.fileExists(atPath: directory.appendingPathComponent("cp-state.initialized").path))
        let recovered = try store.recoverSignedOut(now: CpStoreFixture.now)
        XCTAssertEqual(recovered.session, CpSession())
        XCTAssertNil(recovered.location)
        XCTAssertEqual(recovered.run, CpRun())
        XCTAssertNil(recovered.reading)
        XCTAssertEqual(try store.bootstrap(legacy: CpStoreFixture.legacy, now: CpStoreFixture.now), recovered)
    }
}
