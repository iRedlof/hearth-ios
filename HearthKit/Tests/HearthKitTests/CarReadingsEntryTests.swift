import XCTest
@testable import HearthKit

final class CarReadingsEntryTests: XCTestCase {
    private let observed = Date(timeIntervalSince1970: 1_800_000_000)
    private let raw = #"{"found":true,"prefix":"stargate","name":"Same name","s":{"sensor.battery_level":"79","lock.lock":"locked","sensor.charger_power":"7.25"}}"#

    private func directory() throws -> URL {
        let location = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: location, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: location) }
        return location
    }

    private func envelope() throws -> CarLiveEnvelope {
        let cache = try carReadingsAfterReply(raw, previous: nil, checkedAt: observed)
        let result = CarFetchResult(cache: cache)
        return CarLiveEnvelope(snapshot: result.snapshot(now: observed), result: result,
            origin: CarReadingOrigin(requestScope: "account-A", readRevision: "account-A",
                vehiclePrefix: "stargate", status: .readings, configReady: true,
                observedAt: observed, displayedObservedAt: observed,
                attemptedAt: observed, historical: false), requestReply: .success(raw))
    }

    // Publishing an ID without saving the supplied envelope breaks the widget's launch record.
    func testPublishedDestinationReopensTheExactBoundEnvelope() throws {
        let location = try directory()
        let store = CarReadingsTicketStore(directory: location)
        let supplied = try envelope()
        let entryID = UUID(), ticketID = UUID(), issued = observed.addingTimeInterval(5)
        var saves = 0
        let entry = bindCarReadingsEntry(supplied, entryID: entryID, ticketID: ticketID, date: issued) {
            saves += 1
            try store.save($0, now: issued)
        }
        XCTAssertEqual(entry.entryID, entryID)
        XCTAssertEqual(entry.date, issued)
        XCTAssertEqual(entry.snapshot, supplied.snapshot)
        XCTAssertEqual(entry.destination, .ticket(ticketID))
        XCTAssertEqual(saves, 1)
        guard case .available(let restored) = try CarReadingsTicketStore(directory: location)
            .lookup(ticketID, now: issued) else {
            return XCTFail("The published ticket must reopen")
        }
        XCTAssertEqual(restored.id, ticketID)
        XCTAssertEqual(restored.entryID, entryID)
        XCTAssertEqual(restored.issuedAt, issued)
        XCTAssertEqual(restored.expiresAt, issued.addingTimeInterval(172_800))
        XCTAssertEqual(restored.origin.requestScope, "account-A")
        XCTAssertEqual(restored.origin.readRevision, "account-A")
        XCTAssertEqual(restored.origin.vehiclePrefix, "stargate")
        XCTAssertEqual(restored.origin.status, .readings)
        XCTAssertEqual(restored.origin.observedAt, observed)
        XCTAssertEqual(restored.origin.displayedObservedAt, observed)
        XCTAssertEqual(restored.origin.attemptedAt, observed)
        XCTAssertFalse(restored.origin.historical)
        XCTAssertTrue(restored.origin.configReady)
        XCTAssertEqual(restored.cache?.current, raw)
        XCTAssertEqual(restored.cache?.lastGood, raw)
        XCTAssertEqual(restored.cache?.checkedAt, observed)
        XCTAssertEqual(restored.cache?.lastGoodCheckedAt, observed)
        XCTAssertNil(restored.error)
        XCTAssertFalse(restored.setup)
        XCTAssertEqual(restored.reply, .success(raw: raw))
    }

    // Reformatting the raw cache instead of copying the supplied snapshot changes the entry.
    func testSuppliedPresentationIsNotRecomputedFromRawReadings() throws {
        let original = try envelope()
        var snapshot = original.snapshot
        snapshot.checkedAt = "Envelope's chosen observation label"
        let supplied = CarLiveEnvelope(snapshot: snapshot, result: original.result,
            origin: original.origin, requestReply: original.requestReply)
        let store = CarReadingsTicketStore(directory: try directory())
        let entry = bindCarReadingsEntry(supplied, date: observed) {
            try store.save($0, now: self.observed)
        }
        XCTAssertEqual(entry.snapshot.checkedAt, "Envelope's chosen observation label")
        XCTAssertEqual(entry.snapshot, snapshot)
        guard case .ticket(let id) = entry.destination,
              case .available(let saved) = try store.lookup(id, now: observed) else {
            return XCTFail("The coherent raw record must still be saved")
        }
        XCTAssertEqual(saved.cache?.current, raw)
        XCTAssertEqual(saved.origin.observedAt, observed)
    }

    // History must retain distinct current and displayed cohorts, not parse the displayed 79%.
    func testHistoryPreservesBothRawCohortsAndObservationDates() throws {
        let unknown = raw.replacingOccurrences(of: #""79""#, with: #""unknown""#)
        let checked = observed.addingTimeInterval(30)
        let cache = CarReadingsCache(current: unknown, lastGood: raw, checkedAt: checked,
            lastGoodCheckedAt: observed)
        let result = CarFetchResult(cache: cache)
        let supplied = CarLiveEnvelope(snapshot: result.snapshot(now: checked), result: result,
            origin: CarReadingOrigin(requestScope: "account-A", readRevision: "account-A",
                vehiclePrefix: "stargate", status: .history, configReady: true,
                observedAt: checked, displayedObservedAt: observed, attemptedAt: checked,
                historical: true), requestReply: .success(unknown))
        let store = CarReadingsTicketStore(directory: try directory())
        let entry = bindCarReadingsEntry(supplied, date: checked) { try store.save($0, now: checked) }
        XCTAssertEqual(entry.snapshot, supplied.snapshot)
        XCTAssertEqual(entry.snapshot.battery, 79)
        XCTAssertTrue(entry.snapshot.stale)
        guard case .ticket(let id) = entry.destination,
              case .available(let saved) = try store.lookup(id, now: checked) else {
            return XCTFail("History remains eligible for an explanatory ticket")
        }
        XCTAssertEqual(saved.cache?.current, unknown)
        XCTAssertEqual(saved.cache?.lastGood, raw)
        XCTAssertEqual(saved.cache?.checkedAt, checked)
        XCTAssertEqual(saved.cache?.lastGoodCheckedAt, observed)
        XCTAssertEqual(saved.origin.observedAt, checked)
        XCTAssertEqual(saved.origin.displayedObservedAt, observed)
        XCTAssertEqual(saved.origin.status, .history)
        XCTAssertTrue(saved.origin.historical)
        XCTAssertEqual(saved.reply, .success(raw: unknown))
    }

    // Saving cannot promote setup, anonymous, obsolete, or storage-failure origins to readings.
    func testNonReadingEnvelopesKeepTheirExactStatusAndNonoperatingValidation() throws {
        let emptyRaw = #"{"found":true,"prefix":"stargate","name":"Same name","s":{"sensor.battery_level":"unknown"}}"#
        let unidentifiedRaw = #"{"found":true,"name":"Same name","s":{"sensor.battery_level":"unknown"}}"#
        let noCarRaw = #"{"found":false}"#
        let cases: [(CarOriginStatus, String?, String?, String?, Bool, CarReadingsRouteStatus)] = [
            (.setup, nil, nil, nil, true, .explanationOnly),
            (.authenticationFailure, nil, nil, "Sign in again", false, .explanationOnly),
            (.noCar, noCarRaw, nil, nil, false, .explanationOnly),
            (.unidentified, unidentifiedRaw, nil, nil, false, .explanationOnly),
            (.noReading, emptyRaw, "stargate", nil, false, .configurationChanged),
            (.obsolete, nil, nil, "Configuration changed · Refresh to check", false, .superseded),
            (.storageUnavailable, nil, nil, "Can't read settings · Reopen Hearth", false, .storageUnavailable)
        ]
        let store = CarReadingsTicketStore(directory: try directory())
        let context = HaStoreSnapshot(config: nil, scope: "account-A")
        for (status, reply, prefix, error, setup, expectedValidation) in cases {
            let cache = try reply.map { try carReadingsAfterReply($0, previous: nil, checkedAt: observed) }
            let result = CarFetchResult(cache: cache, error: error, setup: setup)
            let origin = CarReadingOrigin(requestScope: "account-A", readRevision: "account-A",
                vehiclePrefix: prefix, status: status, configReady: !setup,
                observedAt: cache == nil ? nil : observed,
                displayedObservedAt: result.displayedObservedAt, attemptedAt: observed, historical: false)
            let transport: Result<String, HaError>? = status == .authenticationFailure
                ? .failure(HaError("Full authentication failure", code: 401))
                : reply.map { .success($0) }
            let supplied = CarLiveEnvelope(snapshot: result.snapshot(now: observed), result: result,
                origin: origin, requestReply: transport)
            let entry = bindCarReadingsEntry(supplied, date: observed) {
                try store.save($0, now: self.observed)
            }
            XCTAssertEqual(entry.snapshot, supplied.snapshot, status.rawValue)
            guard case .ticket(let id) = entry.destination,
                  case .available(let saved) = try store.lookup(id, now: observed) else {
                XCTFail("Status \(status) must be saved without requiring telemetry")
                continue
            }
            XCTAssertEqual(saved.origin, origin)
            XCTAssertEqual(saved.cache?.current, reply)
            XCTAssertEqual(saved.error, error)
            XCTAssertEqual(saved.setup, setup)
            XCTAssertEqual(saved.validation(in: context, now: observed), expectedValidation)
            if status == .authenticationFailure {
                XCTAssertEqual(saved.reply, .failure(message: "Full authentication failure", code: 401))
            } else {
                XCTAssertEqual(saved.reply, reply.map { .success(raw: $0) })
            }
            XCTAssertFalse(saved.origin.isOperating)
        }
    }

    // Refresh errors must preserve the actual cache and full transport failure.
    func testAuthenticationFailureRetainsTheDisplayedCacheAndFullError() throws {
        let base = try envelope()
        let attempted = observed.addingTimeInterval(60)
        let result = CarFetchResult(cache: base.result.cache, error: "Sign in again")
        let supplied = CarLiveEnvelope(snapshot: result.snapshot(now: attempted), result: result,
            origin: CarReadingOrigin(requestScope: "account-A", readRevision: "account-A",
                vehiclePrefix: "stargate", status: .authenticationFailure, configReady: true,
                observedAt: observed, displayedObservedAt: observed, attemptedAt: attempted,
                historical: true), requestReply: .failure(HaError("Full failure evidence", code: 401)))
        let store = CarReadingsTicketStore(directory: try directory())
        let entry = bindCarReadingsEntry(supplied, date: attempted) {
            try store.save($0, now: attempted)
        }
        XCTAssertEqual(entry.snapshot, supplied.snapshot)
        XCTAssertTrue(entry.snapshot.needsSignIn)
        guard case .ticket(let id) = entry.destination,
              case .available(let saved) = try store.lookup(id, now: attempted) else {
            return XCTFail("Authentication errors must not drop the displayed record")
        }
        XCTAssertEqual(saved.cache?.current, raw)
        XCTAssertEqual(saved.cache?.lastGood, raw)
        XCTAssertEqual(saved.origin.observedAt, observed)
        XCTAssertEqual(saved.origin.attemptedAt, attempted)
        XCTAssertEqual(saved.error, "Sign in again")
        XCTAssertEqual(saved.reply, .failure(message: "Full failure evidence", code: 401))
    }

    // Every new entry must own its record; default IDs must not reuse a latest ticket.
    func testNewEntriesHaveDistinctEntryAndTicketIDs() throws {
        let supplied = try envelope()
        let store = CarReadingsTicketStore(directory: try directory())
        let first = bindCarReadingsEntry(supplied, date: observed) { try store.save($0, now: self.observed) }
        let second = bindCarReadingsEntry(supplied, date: observed) { try store.save($0, now: self.observed) }
        XCTAssertNotEqual(first.entryID, second.entryID)
        guard case .ticket(let firstID) = first.destination,
              case .ticket(let secondID) = second.destination else {
            return XCTFail("Both entries must publish their own persisted ticket")
        }
        XCTAssertNotEqual(firstID, secondID)
        guard case .available(let firstSaved) = try store.lookup(firstID, now: observed),
              case .available(let secondSaved) = try store.lookup(secondID, now: observed) else {
            return XCTFail("Both entry records must remain reachable")
        }
        XCTAssertEqual(firstSaved.entryID, first.entryID)
        XCTAssertEqual(secondSaved.entryID, second.entryID)
    }

    // Retrying one prepared entry must not issue again or extend its fixed expiry.
    func testRepeatedDeliveryOfPreparedEntryKeepsItsOriginalExpiry() throws {
        let supplied = try envelope()
        let entryID = UUID(), ticketID = UUID(), store = CarReadingsTicketStore(directory: try directory())
        let first = bindCarReadingsEntry(supplied, entryID: entryID, ticketID: ticketID, date: observed) {
            try store.save($0, now: self.observed)
        }
        let redelivered = bindCarReadingsEntry(supplied, entryID: entryID, ticketID: ticketID, date: observed) {
            try store.save($0, now: self.observed.addingTimeInterval(60))
        }
        XCTAssertEqual(redelivered, first)
        guard case .available(let saved) = try store.lookup(ticketID,
            now: observed.addingTimeInterval(172_799)) else {
            return XCTFail("A redelivered ticket remains available until its original expiry")
        }
        XCTAssertEqual(saved.issuedAt, observed)
        XCTAssertEqual(saved.expiresAt, observed.addingTimeInterval(172_800))
        XCTAssertEqual(try store.lookup(ticketID, now: observed.addingTimeInterval(172_800)), .expired)
    }

    // Failed persistence must retain the snapshot and never borrow an existing ticket.
    func testMissingStoreAndInjectedSaveFailureNeverPublishAnUnsavedOrExistingUUID() throws {
        let supplied = try envelope()
        let store = CarReadingsTicketStore(directory: try directory())
        let existingID = UUID()
        let existing = bindCarReadingsEntry(supplied, ticketID: existingID, date: observed) {
            try store.save($0, now: self.observed)
        }
        XCTAssertEqual(existing.destination, .ticket(existingID))
        let absentStore: CarReadingsTicketStore? = nil
        for absent in [true, false] {
            let rejectedID = UUID(), entryID = UUID()
            var saves = 0
            let entry = bindCarReadingsEntry(supplied, entryID: entryID, ticketID: rejectedID,
                date: observed) { ticket in
                saves += 1
                if absent {
                    guard let absentStore else { throw CocoaError(.fileNoSuchFile) }
                    try absentStore.save(ticket, now: self.observed)
                } else {
                    throw CocoaError(.fileWriteUnknown)
                }
            }
            XCTAssertEqual(entry.destination, .storageUnavailable)
            XCTAssertEqual(entry.entryID, entryID)
            XCTAssertEqual(entry.date, observed)
            XCTAssertEqual(entry.snapshot, supplied.snapshot)
            XCTAssertEqual(saves, 1)
            XCTAssertEqual(try store.lookup(rejectedID, now: observed), .missing)
            guard case .available(let saved) = try store.lookup(existingID, now: observed) else {
                return XCTFail("A failed entry must not consume or borrow a prior ticket")
            }
            XCTAssertNotEqual(saved.entryID, entry.entryID)
        }
    }

    // The real store's size rejection must not be mistaken for a successful bind.
    func testOversizedRecordKeepsTheSnapshotWithoutOverwritingExistingTicket() throws {
        let location = try directory()
        let store = CarReadingsTicketStore(directory: location)
        let supplied = try envelope(), existingID = UUID(), rejectedID = UUID()
        let existing = bindCarReadingsEntry(supplied, ticketID: existingID, date: observed) {
            try store.save($0, now: self.observed)
        }
        guard existing.destination == .ticket(existingID) else {
            return XCTFail("Oversize failure requires a real prior persisted ticket")
        }
        let file = location.appendingPathComponent("car-readings-tickets.json")
        let before = try Data(contentsOf: file)
        let restricted = CarReadingsTicketStore(directory: location, maximumTicketBytes: 1)
        var saves = 0
        let entry = bindCarReadingsEntry(supplied, ticketID: rejectedID, date: observed) {
            saves += 1
            try restricted.save($0, now: self.observed)
        }
        XCTAssertEqual(entry.destination, .storageUnavailable)
        XCTAssertEqual(entry.snapshot, supplied.snapshot)
        XCTAssertEqual(saves, 1)
        XCTAssertEqual(try Data(contentsOf: file), before)
        XCTAssertEqual(try store.lookup(rejectedID, now: observed), .missing)
        guard case .available = try store.lookup(existingID, now: observed) else {
            return XCTFail("Oversize must not overwrite the previous record")
        }
    }

    // Real corruption and write failures must fail closed without generating an opening ID.
    func testCorruptStoreAndUnwritableLocationKeepCoherentSnapshot() throws {
        let supplied = try envelope()
        let corruptLocation = try directory(), unwritableLocation = try directory()
        let corruptFile = corruptLocation.appendingPathComponent("car-readings-tickets.json")
        let corruptData = Data("invalid JSON".utf8)
        try corruptData.write(to: corruptFile)
        let blocker = unwritableLocation.appendingPathComponent("regular-file")
        try Data("cannot be a directory".utf8).write(to: blocker)
        for location in [corruptLocation, blocker] {
            let store = CarReadingsTicketStore(directory: location), rejectedID = UUID()
            var saves = 0
            let entry = bindCarReadingsEntry(supplied, ticketID: rejectedID, date: observed) {
                saves += 1
                try store.save($0, now: self.observed)
            }
            XCTAssertEqual(entry.destination, .storageUnavailable)
            XCTAssertEqual(entry.snapshot, supplied.snapshot)
            XCTAssertEqual(saves, 1)
            XCTAssertThrowsError(try store.lookup(rejectedID, now: observed))
        }
        XCTAssertEqual(try Data(contentsOf: corruptFile), corruptData)
        XCTAssertEqual(try Data(contentsOf: blocker), Data("cannot be a directory".utf8))
    }

    // An incoherent ticket must fail before persistence, while its presentation stays intact.
    func testTicketConstructionFailureSkipsPersistenceAndDoesNotExposeTicketID() throws {
        let base = try envelope()
        let mismatched = CarLiveEnvelope(snapshot: base.snapshot, result: base.result,
            origin: CarReadingOrigin(requestScope: "account-A", readRevision: "account-A",
                vehiclePrefix: "other_car", status: .readings, configReady: true,
                observedAt: observed, displayedObservedAt: observed, attemptedAt: observed,
                historical: false), requestReply: base.requestReply)
        var saves = 0
        let entry = bindCarReadingsEntry(mismatched, date: observed) { _ in saves += 1 }
        XCTAssertEqual(entry.destination, .storageUnavailable)
        XCTAssertEqual(entry.snapshot, base.snapshot)
        XCTAssertEqual(saves, 0)
    }

    // Nonfinite clocks cannot produce an apparently saved ticket or invoke persistence.
    func testNonfiniteIssuanceDateRetainsSnapshotWithoutPersistence() throws {
        let supplied = try envelope()
        for seconds in [Double.nan, .infinity, -.infinity] {
            var saves = 0
            let entry = bindCarReadingsEntry(supplied, date: Date(timeIntervalSince1970: seconds)) {
                _ in saves += 1
            }
            XCTAssertEqual(entry.destination, .storageUnavailable)
            XCTAssertEqual(entry.snapshot, supplied.snapshot)
            XCTAssertEqual(saves, 0)
        }
    }

    // Eviction after publication cannot redirect the old entry to the newly saved reading.
    func testEvictedEntryHasNoLatestTicketFallback() throws {
        let location = try directory()
        let store = CarReadingsTicketStore(directory: location, maximumCount: 1)
        let supplied = try envelope(), firstID = UUID(), secondID = UUID()
        let first = bindCarReadingsEntry(supplied, ticketID: firstID, date: observed) {
            try store.save($0, now: self.observed)
        }
        let secondDate = observed.addingTimeInterval(1)
        let second = bindCarReadingsEntry(supplied, ticketID: secondID, date: secondDate) {
            try store.save($0, now: secondDate)
        }
        let reopened = CarReadingsTicketStore(directory: location, maximumCount: 1)
        XCTAssertEqual(first.destination, .ticket(firstID))
        XCTAssertEqual(second.destination, .ticket(secondID))
        XCTAssertEqual(try reopened.lookup(firstID, now: secondDate), .missing)
        guard case .available(let saved) = try reopened.lookup(secondID, now: secondDate) else {
            return XCTFail("The new entry must open only its own record")
        }
        XCTAssertEqual(saved.entryID, second.entryID)
        XCTAssertNotEqual(saved.entryID, first.entryID)
    }

    // HA changes during persistence must not rebind the returned payload or stored record.
    func testNewerSameCarCacheAndReplacementAccountCannotChangeTheBoundPayload() throws {
        let config = HaConfig(baseUrl: "https://fixture.example", token: "fixture-only", entityId: "")
        let haStore = HaStateStore(directory: try directory(), initialConfig: config,
            initialScope: "account-A")
        let ticketStore = CarReadingsTicketStore(directory: try directory())
        let supplied = try envelope(), entryID = UUID(), ticketID = UUID()
        let newerTime = observed.addingTimeInterval(60)
        let newerRaw = raw.replacingOccurrences(of: #""79""#, with: #""23""#)
        let entry = bindCarReadingsEntry(supplied, entryID: entryID, ticketID: ticketID, date: observed) {
            try ticketStore.save($0, now: self.observed)
            let owner = try XCTUnwrap(haStore.beginCollectionRead("car",
                expectedScope: "account-A", expectedRevision: "account-A", now: newerTime))
            _ = try XCTUnwrap(haStore.mergeCollection("car", reply: .success(newerRaw),
                expectedScope: "account-A", expectedRevision: "account-A", readID: owner,
                now: newerTime))
        }
        XCTAssertEqual(entry.snapshot, supplied.snapshot)
        XCTAssertEqual(entry.snapshot.battery, 79)
        XCTAssertEqual(entry.entryID, entryID)
        XCTAssertEqual(entry.destination, .ticket(ticketID))
        guard case .available(let saved) = try ticketStore.lookup(ticketID, now: newerTime) else {
            return XCTFail("The captured record must survive the newer cache")
        }
        XCTAssertEqual(saved.cache?.current, raw)
        XCTAssertEqual(saved.cache?.checkedAt, observed)
        XCTAssertEqual(saved.origin.requestScope, "account-A")
        XCTAssertEqual(saved.validation(in: try haStore.snapshot(), now: newerTime), .current)
        _ = try haStore.replaceConfig(HaConfig(baseUrl: "https://replacement.example",
            token: "replacement-fixture-only", entityId: ""))
        XCTAssertEqual(saved.validation(in: try haStore.snapshot(), now: newerTime), .configurationChanged)
        XCTAssertEqual(entry.snapshot, supplied.snapshot)
        XCTAssertEqual(try ticketStore.lookup(ticketID, now: newerTime), .available(saved))
        XCTAssertEqual(saved.cache?.current, raw)
        XCTAssertEqual(saved.origin.vehiclePrefix, "stargate")
    }
}
