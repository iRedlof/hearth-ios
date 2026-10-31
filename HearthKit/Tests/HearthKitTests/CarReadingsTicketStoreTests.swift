import XCTest
@testable import HearthKit

final class CarReadingsTicketStoreTests: XCTestCase {
    private let time = Date(timeIntervalSince1970: 1_800_000_000)
    private let raw = #"{"found":true,"prefix":"stargate","name":"Same name","s":{"sensor.battery_level":"79","lock.lock":"locked"}}"#

    private func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("CarTicketStoreTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    private func ticket(id: UUID = UUID(), issuedAt: Date? = nil, lifetime: TimeInterval = 60,
                        error: String? = nil) throws -> CarReadingsTicket {
        let observed = issuedAt ?? time
        let cache = try carReadingsAfterReply(raw, previous: nil, checkedAt: observed)
        let result = CarFetchResult(cache: cache, error: error)
        let origin = CarReadingOrigin(requestScope: "account-A", readRevision: "account-A",
            vehiclePrefix: "stargate", status: .readings, configReady: true,
            observedAt: observed, displayedObservedAt: observed, attemptedAt: observed,
            historical: false)
        let envelope = CarLiveEnvelope(snapshot: result.snapshot(now: observed), result: result,
            origin: origin, requestReply: .success(raw))
        return try CarReadingsTicket(envelope: envelope, id: id, issuedAt: observed,
            lifetime: lifetime)
    }

    func testSecondInstanceRestoresExactTicketWithoutRebindingItsLifetime() throws {
        let location = try directory()
        let saved = try ticket()
        try CarReadingsTicketStore(directory: location).save(saved, now: time)
        let reopened = CarReadingsTicketStore(directory: location)
        XCTAssertEqual(try reopened.lookup(saved.id, now: time.addingTimeInterval(59)),
            .available(saved))
        XCTAssertEqual(try reopened.lookup(saved.id, now: time.addingTimeInterval(60)), .expired)
        XCTAssertEqual(try reopened.lookup(UUID(), now: time), .missing)
    }

    func testSameIDSameDataSaveIsIdempotentButChangedDataIsRejected() throws {
        let location = try directory()
        let store = CarReadingsTicketStore(directory: location)
        let saved = try ticket()
        try store.save(saved, now: time)
        try store.save(saved, now: time.addingTimeInterval(10))
        let changed = try ticket(id: saved.id, lifetime: 600)
        XCTAssertThrowsError(try store.save(changed, now: time.addingTimeInterval(10))) {
            guard case CarReadingsTicketError.duplicate = $0 else {
                return XCTFail("Expected immutable-ID rejection, got \($0)")
            }
        }
        XCTAssertEqual(try store.lookup(saved.id, now: time.addingTimeInterval(59)), .available(saved))
        XCTAssertEqual(try store.lookup(saved.id, now: time.addingTimeInterval(60)), .expired)
    }

    func testSuccessfulSavePrunesExpiredEntriesAndKeepsNewReading() throws {
        let location = try directory()
        let store = CarReadingsTicketStore(directory: location)
        let expired = try ticket()
        try store.save(expired, now: time)
        let fresh = try ticket(issuedAt: time.addingTimeInterval(60))
        try store.save(fresh, now: time.addingTimeInterval(60))
        XCTAssertEqual(try store.lookup(expired.id, now: time.addingTimeInterval(60)), .missing)
        XCTAssertEqual(try store.lookup(fresh.id, now: time.addingTimeInterval(60)), .available(fresh))
    }

    func testChangedExpiredTicketCannotReuseItsIDBeforePruning() throws {
        let location = try directory()
        let store = CarReadingsTicketStore(directory: location)
        let saved = try ticket()
        try store.save(saved, now: time)
        let changed = try ticket(id: saved.id, issuedAt: time.addingTimeInterval(60))
        XCTAssertThrowsError(try store.save(changed, now: time.addingTimeInterval(60))) {
            guard case CarReadingsTicketError.duplicate = $0 else {
                return XCTFail("Expected immutable-ID rejection, got \($0)")
            }
        }
        XCTAssertEqual(try store.lookup(saved.id, now: time.addingTimeInterval(60)), .expired)
    }

    func testCountEvictionRemovesOldestIssueTimeRegardlessOfSaveOrder() throws {
        let location = try directory()
        let store = CarReadingsTicketStore(directory: location, maximumCount: 2)
        let oldest = try ticket(issuedAt: time, lifetime: 600)
        let middle = try ticket(issuedAt: time.addingTimeInterval(1), lifetime: 600)
        let newest = try ticket(issuedAt: time.addingTimeInterval(2), lifetime: 600)
        try store.save(middle, now: time.addingTimeInterval(2))
        try store.save(oldest, now: time.addingTimeInterval(2))
        try store.save(newest, now: time.addingTimeInterval(2))
        XCTAssertEqual(try store.lookup(oldest.id, now: time.addingTimeInterval(2)), .missing)
        XCTAssertEqual(try store.lookup(middle.id, now: time.addingTimeInterval(2)), .available(middle))
        XCTAssertEqual(try store.lookup(newest.id, now: time.addingTimeInterval(2)), .available(newest))
    }

    func testEqualIssueTimesHaveDeterministicEviction() throws {
        let location = try directory()
        let store = CarReadingsTicketStore(directory: location, maximumCount: 2)
        let first = try ticket(id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!)
        let second = try ticket(id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!)
        let third = try ticket(id: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!)
        try store.save(second, now: time)
        try store.save(first, now: time)
        try store.save(third, now: time)
        XCTAssertEqual(try store.lookup(first.id, now: time), .missing)
        XCTAssertEqual(try store.lookup(second.id, now: time), .available(second))
        XCTAssertEqual(try store.lookup(third.id, now: time), .available(third))
    }

    func testAggregateFileNeverExceedsConfiguredByteBound() throws {
        let location = try directory()
        let store = CarReadingsTicketStore(directory: location, maximumBytes: 2_500,
            maximumTicketBytes: 2_000)
        let oldest = try ticket(issuedAt: time, lifetime: 600,
            error: String(repeating: "x", count: 600))
        let newest = try ticket(issuedAt: time.addingTimeInterval(1), lifetime: 600,
            error: String(repeating: "x", count: 600))
        try store.save(oldest, now: time)
        try store.save(newest, now: time.addingTimeInterval(1))
        let data = try Data(contentsOf: location.appendingPathComponent("car-readings-tickets.json"))
        XCTAssertLessThanOrEqual(data.count, 2_500)
        XCTAssertEqual(try store.lookup(oldest.id, now: time.addingTimeInterval(1)), .missing)
        XCTAssertEqual(try store.lookup(newest.id, now: time.addingTimeInterval(1)), .available(newest))
    }

    func testSuccessfulCountBoundedSaveRetainsIncomingOlderTicketAfterClockRollback() throws {
        let location = try directory()
        let store = CarReadingsTicketStore(directory: location, maximumCount: 1)
        let previous = try ticket(lifetime: 600)
        let incoming = try ticket(issuedAt: time.addingTimeInterval(-60), lifetime: 600)
        try store.save(previous, now: time)
        try store.save(incoming, now: time)
        XCTAssertEqual(try store.lookup(incoming.id, now: time), .available(incoming))
        XCTAssertEqual(try store.lookup(previous.id, now: time), .missing)
    }

    func testSuccessfulByteBoundedSaveRetainsIncomingOlderTicketAfterClockRollback() throws {
        let location = try directory()
        let store = CarReadingsTicketStore(directory: location, maximumBytes: 2_500,
            maximumTicketBytes: 2_000)
        let previous = try ticket(lifetime: 600, error: String(repeating: "x", count: 600))
        let incoming = try ticket(issuedAt: time.addingTimeInterval(-60), lifetime: 600,
            error: String(repeating: "x", count: 600))
        try store.save(previous, now: time)
        try store.save(incoming, now: time)
        XCTAssertEqual(try store.lookup(incoming.id, now: time), .available(incoming))
        XCTAssertEqual(try store.lookup(previous.id, now: time), .missing)
        XCTAssertLessThanOrEqual(try Data(contentsOf: location
            .appendingPathComponent("car-readings-tickets.json")).count, 2_500)
    }

    func testOversizedTicketRejectionLeavesExistingFileAndExpiredEntryUntouched() throws {
        let location = try directory()
        let store = CarReadingsTicketStore(directory: location, maximumTicketBytes: 2_000)
        let saved = try ticket()
        try store.save(saved, now: time)
        let file = location.appendingPathComponent("car-readings-tickets.json")
        let before = try Data(contentsOf: file)
        let oversized = try ticket(issuedAt: time.addingTimeInterval(60),
            error: String(repeating: "x", count: 2_000))
        XCTAssertThrowsError(try store.save(oversized, now: time.addingTimeInterval(60))) {
            guard case CarReadingsTicketError.oversized = $0 else {
                return XCTFail("Expected size rejection, got \($0)")
            }
        }
        XCTAssertEqual(try Data(contentsOf: file), before)
        XCTAssertEqual(try store.lookup(saved.id, now: time.addingTimeInterval(60)), .expired)
    }

    func testSingleTicketThatCannotFitAggregateIsRejectedWithoutOverwrite() throws {
        let location = try directory()
        let store = CarReadingsTicketStore(directory: location, maximumBytes: 1_800,
            maximumTicketBytes: 2_500)
        let saved = try ticket()
        try store.save(saved, now: time)
        let file = location.appendingPathComponent("car-readings-tickets.json")
        let before = try Data(contentsOf: file)
        let tooLarge = try ticket(issuedAt: time.addingTimeInterval(1),
            error: String(repeating: "x", count: 1_000))
        XCTAssertThrowsError(try store.save(tooLarge, now: time.addingTimeInterval(1))) {
            guard case CarReadingsTicketError.oversized = $0 else {
                return XCTFail("Expected aggregate-size rejection, got \($0)")
            }
        }
        XCTAssertEqual(try Data(contentsOf: file), before)
        XCTAssertEqual(try store.lookup(saved.id, now: time), .available(saved))
    }

    func testCorruptionFailsClosedWithoutRegeneratingStore() throws {
        let location = try directory()
        let store = CarReadingsTicketStore(directory: location)
        let saved = try ticket()
        try store.save(saved, now: time)
        let file = location.appendingPathComponent("car-readings-tickets.json")
        let corrupt = Data("broken JSON".utf8)
        try corrupt.write(to: file)
        XCTAssertThrowsError(try store.lookup(saved.id, now: time))
        XCTAssertThrowsError(try store.save(try ticket(), now: time))
        XCTAssertEqual(try Data(contentsOf: file), corrupt)
    }

    func testFutureAggregateVersionIsRejectedWithoutOverwrite() throws {
        let location = try directory()
        let store = CarReadingsTicketStore(directory: location)
        let saved = try ticket()
        try store.save(saved, now: time)
        let file = location.appendingPathComponent("car-readings-tickets.json")
        var value = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: file))
            as? [String: Any])
        value["version"] = 999
        let changed = try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
        try changed.write(to: file)
        XCTAssertThrowsError(try store.lookup(saved.id, now: time))
        XCTAssertThrowsError(try store.save(try ticket(), now: time))
        XCTAssertEqual(try Data(contentsOf: file), changed)
    }

    func testDuplicateIDsInPersistedStoreAreCorruptRatherThanAmbiguousLookup() throws {
        let location = try directory()
        let store = CarReadingsTicketStore(directory: location)
        let saved = try ticket()
        try store.save(saved, now: time)
        let file = location.appendingPathComponent("car-readings-tickets.json")
        var value = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: file))
            as? [String: Any])
        let records = try XCTUnwrap(value["tickets"] as? [[String: Any]])
        value["tickets"] = records + records
        let changed = try JSONSerialization.data(withJSONObject: value)
        try changed.write(to: file)
        XCTAssertThrowsError(try store.lookup(saved.id, now: time))
        XCTAssertThrowsError(try store.save(try ticket(), now: time))
        XCTAssertEqual(try Data(contentsOf: file), changed)
    }

    func testInvalidExpiryInPersistedTicketCannotBeLoaded() throws {
        let location = try directory()
        let store = CarReadingsTicketStore(directory: location)
        let saved = try ticket()
        try store.save(saved, now: time)
        let file = location.appendingPathComponent("car-readings-tickets.json")
        var value = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: file))
            as? [String: Any])
        var records = try XCTUnwrap(value["tickets"] as? [[String: Any]])
        records[0]["expiresAt"] = records[0]["issuedAt"]
        value["tickets"] = records
        let changed = try JSONSerialization.data(withJSONObject: value)
        try changed.write(to: file)
        XCTAssertThrowsError(try store.lookup(saved.id, now: time))
        XCTAssertEqual(try Data(contentsOf: file), changed)
    }

    func testExpiredIncomingTicketCannotTriggerPruningOrAWrite() throws {
        let location = try directory()
        let store = CarReadingsTicketStore(directory: location)
        let saved = try ticket()
        try store.save(saved, now: time)
        let file = location.appendingPathComponent("car-readings-tickets.json")
        let before = try Data(contentsOf: file)
        XCTAssertThrowsError(try store.save(try ticket(), now: time.addingTimeInterval(60))) {
            guard case CarReadingsTicketError.invalid = $0 else {
                return XCTFail("Expected expired incoming ticket rejection, got \($0)")
            }
        }
        XCTAssertEqual(try Data(contentsOf: file), before)
    }

    func testConcurrentInstancesKeepAllDistinctTickets() async throws {
        let location = try directory()
        let baseTime = time
        let tickets = try (0..<32).map {
            try ticket(issuedAt: baseTime.addingTimeInterval(Double($0)), lifetime: 600)
        }
        try await withThrowingTaskGroup(of: Void.self) { group in
            for saved in tickets {
                group.addTask {
                    try CarReadingsTicketStore(directory: location)
                        .save(saved, now: baseTime.addingTimeInterval(32))
                }
            }
            try await group.waitForAll()
        }
        for saved in tickets {
            XCTAssertEqual(try CarReadingsTicketStore(directory: location)
                .lookup(saved.id, now: baseTime.addingTimeInterval(32)), .available(saved))
        }
    }

    func testStoreRestrictsDirectoryDataAndPermanentLockPermissions() throws {
        let location = try directory()
        try FileManager.default.setAttributes([.posixPermissions: 0o777], ofItemAtPath: location.path)
        let store = CarReadingsTicketStore(directory: location)
        try store.save(try ticket(), now: time)
        for (url, expected) in [
            (location, 0o700),
            (location.appendingPathComponent("car-readings-tickets.json"), 0o600),
            (location.appendingPathComponent("car-readings-tickets.lock"), 0o600)
        ] {
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, expected)
        }
        let contents = try FileManager.default.contentsOfDirectory(atPath: location.path)
        XCTAssertEqual(Set(contents), ["car-readings-tickets.json", "car-readings-tickets.lock"])
    }

    func testMissingLookupDoesNotCreateAnEmptyDataRecord() throws {
        let location = try directory()
        let store = CarReadingsTicketStore(directory: location)
        XCTAssertEqual(try store.lookup(UUID(), now: time), .missing)
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: location.appendingPathComponent("car-readings-tickets.json").path))
    }

    func testOversizedPersistedAggregateFailsBeforeDecodeAndRemainsIntact() throws {
        let location = try directory()
        let file = location.appendingPathComponent("car-readings-tickets.json")
        let data = Data(repeating: 32, count: 1_001)
        try data.write(to: file)
        let store = CarReadingsTicketStore(directory: location, maximumBytes: 1_000)
        XCTAssertThrowsError(try store.lookup(UUID(), now: time))
        XCTAssertThrowsError(try store.save(try ticket(), now: time))
        XCTAssertEqual(try Data(contentsOf: file), data)
    }

    func testLimitsRejectInvalidValuesWithoutTouchingTheExistingRecord() throws {
        let location = try directory()
        let saved = try ticket()
        try CarReadingsTicketStore(directory: location).save(saved, now: time)
        let file = location.appendingPathComponent("car-readings-tickets.json")
        let before = try Data(contentsOf: file)
        for (count, bytes, ticketBytes) in [(0, 4_096, 2_000), (1, 0, 2_000), (1, 4_096, -1)] {
            let store = CarReadingsTicketStore(directory: location, maximumCount: count,
                maximumBytes: bytes, maximumTicketBytes: ticketBytes)
            XCTAssertThrowsError(try store.save(saved, now: time))
            XCTAssertThrowsError(try store.lookup(saved.id, now: time))
        }
        XCTAssertEqual(try Data(contentsOf: file), before)
    }

    func testInvalidLookupClockCannotPretendTicketIsExpired() throws {
        let location = try directory()
        let store = CarReadingsTicketStore(directory: location)
        let saved = try ticket()
        try store.save(saved, now: time)
        XCTAssertThrowsError(try store.lookup(saved.id,
            now: Date(timeIntervalSince1970: .nan)))
        XCTAssertEqual(try store.lookup(saved.id, now: time), .available(saved))
    }

    func testSymbolicLockIsRejectedWithoutChangingItsDestination() throws {
        let location = try directory()
        let otherFile = location.appendingPathComponent("other-file")
        let otherData = Data("Other file must remain intact".utf8)
        try otherData.write(to: otherFile)
        try FileManager.default.setAttributes([.posixPermissions: 0o644],
            ofItemAtPath: otherFile.path)
        try FileManager.default.createSymbolicLink(
            at: location.appendingPathComponent("car-readings-tickets.lock"),
            withDestinationURL: otherFile)
        let store = CarReadingsTicketStore(directory: location)
        XCTAssertThrowsError(try store.save(try ticket(), now: time))
        XCTAssertThrowsError(try store.lookup(UUID(), now: time))
        XCTAssertEqual(try Data(contentsOf: otherFile), otherData)
        let attributes = try FileManager.default.attributesOfItem(atPath: otherFile.path)
        XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o644)
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: location.appendingPathComponent("car-readings-tickets.json").path))
    }

    func testSymbolicDataRecordIsRejectedWithoutChangingItsDestination() throws {
        let location = try directory()
        let otherFile = location.appendingPathComponent("other-file")
        let otherData = Data("Other file must remain intact".utf8)
        try otherData.write(to: otherFile)
        try FileManager.default.createSymbolicLink(
            at: location.appendingPathComponent("car-readings-tickets.json"),
            withDestinationURL: otherFile)
        let store = CarReadingsTicketStore(directory: location)
        XCTAssertThrowsError(try store.lookup(UUID(), now: time))
        XCTAssertThrowsError(try store.save(try ticket(), now: time))
        XCTAssertEqual(try Data(contentsOf: otherFile), otherData)
    }

    func testDanglingDataLinkIsCorruptionRatherThanAnEmptyStore() throws {
        let location = try directory()
        let missingDestination = location.appendingPathComponent("missing-file")
        let file = location.appendingPathComponent("car-readings-tickets.json")
        try FileManager.default.createSymbolicLink(at: file, withDestinationURL: missingDestination)
        let store = CarReadingsTicketStore(directory: location)
        XCTAssertThrowsError(try store.lookup(UUID(), now: time))
        XCTAssertThrowsError(try store.save(try ticket(), now: time))
        XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(atPath: file.path),
            missingDestination.path)
    }
}
