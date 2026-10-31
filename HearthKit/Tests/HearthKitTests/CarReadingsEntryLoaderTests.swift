import XCTest
@testable import HearthKit

final class CarReadingsEntryLoaderTests: XCTestCase {
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
        var snapshot = result.snapshot(now: observed)
        snapshot.checkedAt = "Envelope's chosen observation label"
        return CarLiveEnvelope(snapshot: snapshot, result: result,
            origin: CarReadingOrigin(requestScope: "account-A", readRevision: "account-A",
                vehiclePrefix: "stargate", status: .readings, configReady: true,
                observedAt: observed, displayedObservedAt: observed, attemptedAt: observed,
                historical: false), requestReply: .success(raw))
    }

    // Removing the initial inert branch would fetch production data and publish a sample ticket.
    func testInertSelectionReturnsSampleWithoutFetchingOrPersisting() async throws {
        let supplied = try envelope(), state = LoaderState(), date = observed
        let payload = await loadCarReadingsEntry(selection: .inert, sample: .sample,
            fetchEnvelope: { state.fetched(); return supplied },
            persist: { _, _ in state.saved() }, now: { date })
        XCTAssertEqual(payload.destination, .inert)
        XCTAssertEqual(payload.snapshot, .sample)
        XCTAssertEqual(payload.date, date)
        XCTAssertEqual(state.fetchCount, 0)
        XCTAssertEqual(state.saveCount, 0)
    }

    // Refetching, rebuilding presentation, or publishing another UUID loses the chosen envelope.
    func testLiveSelectionFetchesOnceAndReopensOriginalRawSnapshotAndIDs() async throws {
        let supplied = try envelope(), state = LoaderState(), date = observed.addingTimeInterval(5)
        let location = try directory(), store = CarReadingsTicketStore(directory: location)
        let payload = await loadCarReadingsEntry(selection: .live,
            fetchEnvelope: { state.fetched(); return supplied },
            persist: { ticket, issued in
                state.saved()
                try store.save(ticket, now: issued)
            }, now: { date })
        XCTAssertEqual(state.fetchCount, 1)
        XCTAssertEqual(state.saveCount, 1)
        XCTAssertEqual(payload.snapshot.checkedAt, "Envelope's chosen observation label")
        XCTAssertEqual(payload.snapshot.battery, 79)
        XCTAssertEqual(payload.snapshot, supplied.snapshot)
        XCTAssertEqual(payload.date, date)
        guard case .ticket(let id) = payload.destination,
              case .available(let restored) = try CarReadingsTicketStore(directory: location)
                .lookup(id, now: date) else {
            return XCTFail("Live delivery must publish its own reopened ticket")
        }
        XCTAssertEqual(restored.id, id)
        XCTAssertEqual(restored.entryID, payload.entryID)
        XCTAssertEqual(restored.cache?.current, raw)
        XCTAssertEqual(restored.cache?.checkedAt, observed)
        XCTAssertEqual(restored.origin.requestScope, "account-A")
        XCTAssertEqual(restored.origin.vehiclePrefix, "stargate")
        XCTAssertEqual(restored.reply, .success(raw: raw))
    }

    // Checking the publication guard only before suspension would save a now-inert live entry.
    func testChangedPublicationGuardAfterAwaitPreventsPersistence() async throws {
        let supplied = try envelope(), state = LoaderState(), date = observed
        let gate = SuspendedEntryEnvelope()
        let task = Task {
            await loadCarReadingsEntry(selection: .live, sample: .sample,
                fetchEnvelope: { state.fetched(); return await gate.fetch() },
                persist: { _, _ in state.saved() }, now: { date },
                allowsLivePublication: { state.publicationAllowed })
        }
        await gate.waitUntilRequested()
        state.disallowPublication()
        await gate.finish(supplied)
        let payload = await task.value
        XCTAssertEqual(payload.destination, .inert)
        XCTAssertEqual(payload.snapshot, .sample)
        XCTAssertEqual(state.fetchCount, 1)
        XCTAssertEqual(state.saveCount, 0)
    }

    // A save failure must not replace this entry's presentation or expose an unsaved UUID.
    func testUnavailableStoreKeepsCoherentSnapshotAndExplanationDestination() async throws {
        let supplied = try envelope(), state = LoaderState(), date = observed
        let absentStore: CarReadingsTicketStore? = nil
        let payload = await loadCarReadingsEntry(selection: .live,
            fetchEnvelope: { state.fetched(); return supplied },
            persist: { ticket, issued in
                state.saved()
                guard let absentStore else { throw CocoaError(.fileNoSuchFile) }
                try absentStore.save(ticket, now: issued)
            }, now: { date })
        XCTAssertEqual(payload.destination, .storageUnavailable)
        XCTAssertEqual(payload.snapshot, supplied.snapshot)
        XCTAssertEqual(payload.date, date)
        XCTAssertEqual(state.fetchCount, 1)
        XCTAssertEqual(state.saveCount, 1)
        XCTAssertEqual(carReadingsURL(for: payload.destination)?.absoluteString,
            "hearth://car-readings/unavailable")
    }

    // Taking issuance before await, or a second persistence clock, can prematurely expire a ticket.
    func testPostFetchIssuanceClockIsCapturedOnceAndUsedByReopenedStore() async throws {
        let supplied = try envelope(), state = LoaderState(date: observed)
        let issued = observed.addingTimeInterval(200_000)
        let location = try directory(), store = CarReadingsTicketStore(directory: location)
        let payload = await loadCarReadingsEntry(selection: .live,
            fetchEnvelope: {
                state.setDate(issued)
                return supplied
            }, persist: { ticket, date in
                XCTAssertEqual(date, issued)
                try store.save(ticket, now: date)
                state.setDate(issued.addingTimeInterval(200_000))
            }, now: { state.readDate() })
        XCTAssertEqual(state.clockCount, 1)
        XCTAssertEqual(payload.date, issued)
        guard case .ticket(let id) = payload.destination,
              case .available(let restored) = try CarReadingsTicketStore(directory: location)
                .lookup(id, now: issued) else {
            return XCTFail("Persistence must use the captured post-fetch issuance date")
        }
        XCTAssertEqual(restored.issuedAt, issued)
        XCTAssertEqual(restored.expiresAt, issued.addingTimeInterval(172_800))
        XCTAssertEqual(try store.lookup(id, now: issued.addingTimeInterval(172_800)), .expired)
    }
}

private final class LoaderState: @unchecked Sendable {
    private let lock = NSLock()
    private var fetches = 0
    private var saves = 0
    private var clocks = 0
    private var allowed = true
    private var date: Date

    init(date: Date = .distantPast) { self.date = date }
    var fetchCount: Int { lock.withLock { fetches } }
    var saveCount: Int { lock.withLock { saves } }
    var clockCount: Int { lock.withLock { clocks } }
    var publicationAllowed: Bool { lock.withLock { allowed } }
    func fetched() { lock.withLock { fetches += 1 } }
    func saved() { lock.withLock { saves += 1 } }
    func disallowPublication() { lock.withLock { allowed = false } }
    func setDate(_ value: Date) { lock.withLock { date = value } }
    func readDate() -> Date { lock.withLock { clocks += 1; return date } }
}

private actor SuspendedEntryEnvelope {
    private var continuation: CheckedContinuation<CarLiveEnvelope, Never>?
    private var startWaiters: [CheckedContinuation<Void, Never>] = []

    func fetch() async -> CarLiveEnvelope {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            for waiter in startWaiters { waiter.resume() }
            startWaiters = []
        }
    }

    func waitUntilRequested() async {
        guard continuation == nil else { return }
        await withCheckedContinuation { startWaiters.append($0) }
    }

    func finish(_ envelope: CarLiveEnvelope) {
        continuation?.resume(returning: envelope)
        continuation = nil
    }
}
