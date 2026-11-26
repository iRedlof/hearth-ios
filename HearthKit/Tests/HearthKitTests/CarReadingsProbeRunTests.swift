#if DEBUG
import XCTest
@testable import HearthKit

final class CarReadingsProbeRunTests: XCTestCase {
    private let clock = Date(timeIntervalSince1970: 1_800_000_000)

    private func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    private func newRun() throws -> CarRouteProbeRun {
        try CarRouteProbeRun(runID: UUID(), generation: UUID(), scenario: .current,
            fixtureClock: clock)
    }

    // Removing sticky isolation would construct the ordinary app after control storage disappears.
    func testMissingAndUnreadableControlStayBlockedWhenIsolationWasRequired() {
        for record in [CarRouteProbeControlRead.absent, .unavailable, .invalid] {
            guard case .blocked = CarRouteProbeLaunchResolver.resolve(arguments: [],
                isolationRequired: true, control: record) else {
                return XCTFail("Required isolation must never fall through")
            }
        }
        XCTAssertEqual(CarRouteProbeLaunchResolver.resolve(arguments: [],
            isolationRequired: false, control: .absent), .inactive)
    }

    // Treating a bad arming selector as absent would activate the live destination.
    func testInvalidMissingAndRepeatedSelectorsStayBlocked() {
        for args in [["-carWidgetProbe"], ["-carWidgetProbe", "../HAState"],
                     ["-carWidgetProbe", "current", "-carWidgetProbe", "setup"]] {
            guard case .blocked = CarRouteProbeLaunchResolver.resolve(arguments: args,
                isolationRequired: false, control: .absent) else {
                return XCTFail("Invalid explicit probe launch must be inert")
            }
        }
    }

    // Old fixture/parity flags must not override a valid private persisted run.
    func testPersistedRunWinsFixtureAndParitySelectors() throws {
        let value = try newRun()
        XCTAssertEqual(CarRouteProbeLaunchResolver.resolve(
            arguments: ["-carRouteFixture", "auth", "-parityLive", "-parityState", "car-ok"],
            isolationRequired: false, control: .active(value)), .armed(value))
    }

    // Reading only the manifest marker would accept a run built for a different executable.
    func testStaleBuildAndDisabledControlStayBlocked() throws {
        let stale = try CarRouteProbeRun(runID: UUID(), generation: UUID(), buildMarker: "old-build",
            scenario: .current, fixtureClock: clock)
        for record in [CarRouteProbeControlRead.active(stale), .disabled] {
            guard case .blocked = CarRouteProbeLaunchResolver.resolve(arguments: [],
                isolationRequired: false, control: record) else {
                return XCTFail("Disabled or mismatched probe must not become live")
            }
        }
    }

    // Activation before preparation, or reconstructing missing directories, would silently reseed.
    func testActivationRequiresPreparedRunAndReopenedStoreRetainsIdentity() throws {
        let root = try directory(), value = try newRun(), store = CarRouteProbeControlStore(root: root)
        XCTAssertThrowsError(try store.activate(value))
        try store.prepare(value)
        try store.activate(value)
        XCTAssertEqual(CarRouteProbeControlStore(root: root).read(), .active(value))
        try FileManager.default.removeItem(at: store.runDirectory(value).appendingPathComponent("HA"))
        XCTAssertEqual(store.read(), .invalid)
    }

    // Decoding oversized or untrusted control without validation can select arbitrary storage.
    func testCorruptOversizedAndUnknownVersionControlAreRejected() throws {
        let root = try directory(), store = CarRouteProbeControlStore(root: root), value = try newRun()
        try store.prepare(value)
        try store.activate(value)
        let file = root.appendingPathComponent("control.json")
        let valid = try Data(contentsOf: file)
        try Data("{broken".utf8).write(to: file, options: .atomic)
        XCTAssertEqual(store.read(), .invalid)
        try Data(repeating: 32, count: 65_537).write(to: file, options: .atomic)
        XCTAssertEqual(store.read(), .invalid)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: valid) as? [String: Any])
        object["version"] = 2
        try JSONSerialization.data(withJSONObject: object).write(to: file, options: .atomic)
        XCTAssertEqual(store.read(), .invalid)
    }

    // Accepting missing slots, unbounded clocks, or malformed run identities breaks captured input.
    func testRunDecoderRejectsInvalidSlotsScenarioClockAndUUID() throws {
        let data = try JSONEncoder().encode(newRun())
        let original = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let mutations: [(String, Any)] = [("slots", ["A"]), ("scenario", "network"),
            ("fixtureClock", -10_000_000_000.0), ("runID", "../../HAState"), ("version", 2)]
        for (key, value) in mutations {
            var object = original
            object[key] = value
            XCTAssertThrowsError(try JSONDecoder().decode(CarRouteProbeRun.self,
                from: JSONSerialization.data(withJSONObject: object)))
        }
    }

    // Disarming must keep a persisted record so extension and app never revert to live.
    func testDisarmRetainsControlAndInvalidatesOldGeneration() throws {
        let store = CarRouteProbeControlStore(root: try directory()), value = try newRun()
        try store.prepare(value)
        try store.activate(value)
        XCTAssertTrue(store.isCurrent(value))
        try store.disable()
        XCTAssertEqual(store.read(), .disabled)
        XCTAssertFalse(store.isCurrent(value))
        let next = try newRun()
        try store.prepare(next)
        try store.activate(next)
        XCTAssertFalse(store.isCurrent(value))
        XCTAssertTrue(store.isCurrent(next))
    }
    // Arming must initialize a private account but never fabricate a provider ticket or cache.
    func testSeedAndActivateCreatesOnlyPrivateStateWithoutReadingOrTicket() throws {
        let store = CarRouteProbeControlStore(root: try directory()), value = try newRun()
        try store.seedAndActivate(value)
        let dependencies = try CarRouteProbeDependencies(run: value, slot: .a, control: store)
        let context = try dependencies.state.snapshot()
        XCTAssertEqual(context.scope, value.runID.uuidString)
        XCTAssertEqual(context.config?.baseUrl, "https://fixture.example")
        XCTAssertTrue(context.collectionCaches.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.runDirectory(value)
            .appendingPathComponent("Tickets/car-readings-tickets.json").path))
        XCTAssertEqual(dependencies.counts.fetch, 0)
        XCTAssertEqual(dependencies.counts.save, 0)
        XCTAssertEqual(dependencies.counts.transport, 0)
    }

    // Losing the private state after arming must block rather than seed a replacement account.
    func testCapturedDependenciesRejectMissingStateAndDisabledIdentity() throws {
        let store = CarRouteProbeControlStore(root: try directory()), value = try newRun()
        try store.seedAndActivate(value)
        try FileManager.default.removeItem(at: store.runDirectory(value).appendingPathComponent("HA/ha-state.json"))
        XCTAssertThrowsError(try CarRouteProbeDependencies(run: value, slot: .a, control: store))
        try store.disable()
        XCTAssertThrowsError(try CarRouteProbeDependencies(run: value, slot: .b, control: store))
    }

    // Substituting a fixture snapshot or a second fetch would lose the owned raw envelope/ticket.
    func testEachSlotPublishesOwnEnvelopeAndPersistedTicketThroughRealLoader() async throws {
        let store = CarRouteProbeControlStore(root: try directory()), value = try newRun()
        try store.seedAndActivate(value)
        for (slot, battery) in [(CarRouteProbeSlot.a, 79), (.b, 44)] {
            let dependencies = try CarRouteProbeDependencies(run: value, slot: slot, control: store)
            let date = dependencies.issuanceClock
            let payload = await loadCarReadingsEntry(selection: .live,
                fetchEnvelope: dependencies.fetchEnvelope, persist: dependencies.persist,
                now: { date }, allowsLivePublication: dependencies.allowsPublication)
            XCTAssertEqual(payload.snapshot.battery, battery)
            guard case .ticket(let id) = payload.destination,
                  case .available(let ticket) = try dependencies.tickets.lookup(id, now: date) else {
                return XCTFail("The actual entry must retain its exact ticket")
            }
            XCTAssertEqual(ticket.entryID, payload.entryID)
            XCTAssertEqual(ticket.origin.requestScope, value.runID.uuidString)
            XCTAssertEqual(ticket.origin.vehiclePrefix, "stargate")
            XCTAssertEqual(ticket.origin.observedAt, date)
            XCTAssertEqual(dependencies.counts.fetch, 1)
            XCTAssertEqual(dependencies.counts.save, 1)
            XCTAssertEqual(dependencies.counts.transport, 1)
        }
    }

    // Persistence failure must publish only reserved-unavailable; expired uses normal 48h lifetime.
    func testControlledFailureSetupAuthenticationAndExpiryUseRealFactory() async throws {
        for scenario in [CarRouteProbeScenario.persistenceFailure, .setup, .authentication, .expired] {
            let store = CarRouteProbeControlStore(root: try directory())
            let value = try CarRouteProbeRun(runID: UUID(), generation: UUID(), scenario: scenario,
                fixtureClock: clock)
            try store.seedAndActivate(value)
            let dependencies = try CarRouteProbeDependencies(run: value, slot: .a, control: store)
            let date = dependencies.issuanceClock
            let payload = await loadCarReadingsEntry(selection: .live,
                fetchEnvelope: dependencies.fetchEnvelope, persist: dependencies.persist,
                now: { date }, allowsLivePublication: dependencies.allowsPublication)
            if scenario == .persistenceFailure {
                XCTAssertEqual(payload.destination, .storageUnavailable)
            } else {
                guard case .ticket(let id) = payload.destination else { return XCTFail("A saved ticket is required") }
                if scenario == .expired {
                    XCTAssertEqual(date, clock.addingTimeInterval(-172_860))
                    XCTAssertEqual(try dependencies.tickets.lookup(id, now: clock), .expired)
                    guard case .available(let ticket) = try dependencies.tickets.lookup(id, now: date) else {
                        return XCTFail("Expired fixture must save coherently at its exact old issuance clock")
                    }
                    XCTAssertEqual(ticket.expiresAt.timeIntervalSince(ticket.issuedAt), 172_800)
                } else {
                    guard case .available(let ticket) = try dependencies.tickets.lookup(id, now: clock) else {
                        return XCTFail("Fixture record must reopen")
                    }
                    XCTAssertEqual(ticket.origin.status, scenario == .setup ? .setup : .authenticationFailure)
                    XCTAssertEqual(dependencies.counts.transport, scenario == .setup ? 0 : 1)
                }
            }
        }
    }

    // A captured generation may finish after disarm, but it must never save or publish a URL.
    func testDisarmedCapturedDependenciesPreventLateSaveAndPublication() async throws {
        let store = CarRouteProbeControlStore(root: try directory()), value = try newRun()
        try store.seedAndActivate(value)
        let dependencies = try CarRouteProbeDependencies(run: value, slot: .a, control: store)
        let envelope = await dependencies.fetchEnvelope()
        let ticket = try CarReadingsTicket(envelope: envelope, issuedAt: clock)
        try store.disable()
        XCTAssertFalse(dependencies.allowsPublication())
        XCTAssertThrowsError(try dependencies.persist(ticket, clock))
        XCTAssertEqual(try dependencies.tickets.lookup(ticket.id, now: clock), .missing)
    }

    // Receipts must retain common identity and bound disk use without accepting credentials/URLs.
    func testReceiptsAreAtomicBoundedAndExcludeUntrustedFields() throws {
        let store = CarRouteProbeControlStore(root: try directory()), value = try newRun()
        try store.seedAndActivate(value)
        let writer = CarRouteProbeReceiptWriter(run: value, slot: .b,
            directory: store.runDirectory(value).appendingPathComponent("Receipts"), maximumCount: 2)
        XCTAssertNotNil(writer.record(phase: "sceneReceived", fields: ["ticketID": UUID().uuidString,
            "runID": "wrong", "token": "secret", "url": "https://private.invalid/?secret",
            "snapshotName": "https://private.invalid"]))
        XCTAssertNotNil(writer.record(phase: "screenLoaded"))
        XCTAssertNil(writer.record(phase: "screenClosed"))
        let urls = try FileManager.default.contentsOfDirectory(
            at: store.runDirectory(value).appendingPathComponent("Receipts"), includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }
        XCTAssertEqual(urls.count, 2)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: urls[0])) as? [String: Any])
        XCTAssertEqual(object["runID"] as? String, value.runID.uuidString)
        XCTAssertEqual(object["generation"] as? String, value.generation.uuidString)
        XCTAssertEqual(object["buildMarker"] as? String, "car-route-probe-2026-10-31-v1")
        XCTAssertEqual(object["slot"] as? String, "B")
        XCTAssertNotNil(object["eventID"])
        XCTAssertNotNil(object["processInstanceID"])
        let fields = try XCTUnwrap(object["fields"] as? [String: String])
        XCTAssertNil(fields["token"])
        XCTAssertNil(fields["url"])
        XCTAssertNil(fields["snapshotName"])
    }

    // Removing the barrier would let A finish before a competing real B route can be staged.
    func testControlledRefreshWaitsForItsOwnRunAndRequestRelease() async throws {
        let store = CarRouteProbeControlStore(root: try directory()), value = try newRun()
        try store.seedAndActivate(value)
        try store.setRefreshBarrier(run: value, held: true)
        let dependencies = try CarRouteProbeDependencies(run: value, slot: .a, control: store)
        let task = Task { try await dependencies.request() }
        let folder = store.runDirectory(value).appendingPathComponent("Receipts")
        var enteredID: UUID?
        for _ in 0..<100 {
            let files = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
            for file in files where file.pathExtension == "json" {
                let object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any])
                if object["phase"] as? String == "requestEntered", let fields = object["fields"] as? [String: String] {
                    enteredID = fields["requestID"].flatMap(UUID.init(uuidString:))
                }
            }
            if enteredID != nil { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        let id = try XCTUnwrap(enteredID)
        try store.releaseRequest(run: value, requestID: UUID())
        try await Task.sleep(for: .milliseconds(100))
        let before = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
        let phases = try before.filter { $0.pathExtension == "json" }.map {
            try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: $0)) as? [String: Any])["phase"] as? String
        }
        XCTAssertFalse(phases.contains("transportCompleted"))
        try store.releaseRequest(run: value, requestID: id)
        let raw = try await task.value
        XCTAssertEqual(carFromTemplate(raw)?.battery, 80)
    }

    // Cancellation or expiry must end the controlled request without substituting a live transport.
    func testHeldControlledRefreshTimesOutAndCancelledRequestDoesNotComplete() async throws {
        let store = CarRouteProbeControlStore(root: try directory()), value = try newRun()
        try store.seedAndActivate(value)
        try store.setRefreshBarrier(run: value, held: true)
        let dependencies = try CarRouteProbeDependencies(run: value, slot: .a, control: store,
            barrierTimeout: 0.05)
        do { _ = try await dependencies.request(); XCTFail("Held request must time out") }
        catch { XCTAssertEqual((error as? HaError)?.message, "The controlled Refresh barrier timed out.") }
        let other = try CarRouteProbeDependencies(run: value, slot: .a, control: store)
        let task = Task { try await other.request() }
        task.cancel()
        do { _ = try await task.value; XCTFail("Cancelled controlled request must not finish") }
        catch { XCTAssertTrue(error is CancellationError) }
    }

    // A digest over only battery/name cannot join the full immutable reading record.
    func testTicketDigestCoversCompleteCanonicalTicket() async throws {
        let store = CarRouteProbeControlStore(root: try directory()), value = try newRun()
        try store.seedAndActivate(value)
        let dependencies = try CarRouteProbeDependencies(run: value, slot: .a, control: store)
        let envelope = await dependencies.fetchEnvelope()
        let ticket = try CarReadingsTicket(envelope: envelope, issuedAt: clock)
        let digest = try CarRouteProbeReceiptWriter.ticketDigest(ticket)
        XCTAssertEqual(digest.count, 64)
        XCTAssertEqual(digest, try CarRouteProbeReceiptWriter.ticketDigest(
            JSONDecoder().decode(CarReadingsTicket.self, from: JSONEncoder().encode(ticket))))
        let different = try CarReadingsTicket(envelope: envelope, entryID: ticket.entryID,
            id: ticket.id, issuedAt: clock.addingTimeInterval(1))
        XCTAssertNotEqual(digest, try CarRouteProbeReceiptWriter.ticketDigest(different))
    }

    // A later missing file must never become an empty setup account under a captured active run.
    func testMissingPrivateHAAfterCaptureRejectsStateFetchAndPublicationWithoutRecreatingFile() async throws {
        let store = CarRouteProbeControlStore(root: try directory()), value = try newRun()
        try store.seedAndActivate(value)
        let dependencies = try CarRouteProbeDependencies(run: value, slot: .a, control: store)
        let file = store.runDirectory(value).appendingPathComponent("HA/ha-state.json")
        try FileManager.default.removeItem(at: file)
        XCTAssertThrowsError(try dependencies.state.snapshot())
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
        let envelope = await dependencies.fetchEnvelope()
        XCTAssertEqual(envelope.origin.status, .storageUnavailable)
        XCTAssertFalse(envelope.result.setup)
        XCTAssertFalse(dependencies.allowsPublication())
        let ticket = try CarReadingsTicket(envelope: envelope, issuedAt: clock)
        XCTAssertThrowsError(try dependencies.persist(ticket, clock))
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.runDirectory(value)
            .appendingPathComponent("Tickets/car-readings-tickets.json").path))
    }

    // Valid JSON padding must fail the byte limit, rather than pass an unbounded decode.
    func testOversizedPrivateHARejectsCaptureAndLaterLockedStateReadWithoutReplacingBytes() async throws {
        let store = CarRouteProbeControlStore(root: try directory()), value = try newRun()
        try store.seedAndActivate(value)
        let dependencies = try CarRouteProbeDependencies(run: value, slot: .a, control: store)
        let file = store.runDirectory(value).appendingPathComponent("HA/ha-state.json")
        var oversized = try Data(contentsOf: file)
        oversized.append(Data(repeating: 32, count: 65_537 - oversized.count))
        try oversized.write(to: file, options: .atomic)
        XCTAssertThrowsError(try CarRouteProbeDependencies(run: value, slot: .b, control: store))
        XCTAssertThrowsError(try dependencies.state.snapshot())
        let envelope = await dependencies.fetchEnvelope()
        XCTAssertEqual(envelope.origin.status, .storageUnavailable)
        XCTAssertFalse(dependencies.allowsPublication())
        XCTAssertEqual(try Data(contentsOf: file), oversized)
    }

    // The app runtime's exact transport does not own a provider slot, even when B is opened.
    func testHostEquivalentBRefreshTransportUsesAppIdentityWhileProviderRetainsB() async throws {
        let store = CarRouteProbeControlStore(root: try directory()), value = try newRun()
        try store.seedAndActivate(value)
        let host = try CarRouteProbeDependencies(run: value, slot: .a, control: store)
        let providerB = try CarRouteProbeDependencies(run: value, slot: .b, control: store)
        let date = providerB.issuanceClock
        let payload = await loadCarReadingsEntry(selection: .live,
            fetchEnvelope: providerB.fetchEnvelope, persist: providerB.persist,
            now: { date }, allowsLivePublication: providerB.allowsPublication)
        guard case .ticket(let id) = payload.destination,
              case .available(let ticket) = try host.tickets.lookup(id, now: date),
              let prefix = ticket.origin.vehiclePrefix else { return XCTFail("B must save its own reading") }
        providerB.receipts.record(phase: "providerCompleted", fields: ["ticketID": id.uuidString])
        let reply = await fetchOwnedCarRouteEnvelope(store: host.state, context: try host.state.snapshot(),
            expectedVehiclePrefix: prefix, now: date, request: host.request, observedNow: { date })
        XCTAssertEqual(reply.snapshot.battery, 80)
        let files = try FileManager.default.contentsOfDirectory(
            at: store.runDirectory(value).appendingPathComponent("Receipts"), includingPropertiesForKeys: nil)
        let records = try files.filter { $0.pathExtension == "json" }.map {
            try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: $0)) as? [String: Any])
        }
        let transports = records.filter { ["requestEntered", "transportCompleted"].contains($0["phase"] as? String ?? "") }
        XCTAssertEqual(transports.count, 2)
        XCTAssertTrue(transports.allSatisfy { $0["slot"] as? String == "app" })
        XCTAssertEqual(records.first { $0["phase"] as? String == "providerCompleted" }?["slot"] as? String, "B")
    }

    // Process death before rename leaves a stage that still consumes private disk and file quota.
    func testOrphanReceiptStagesCountTowardCountAndByteBudgetsWithoutDeletingFinalReceipts() throws {
        for useBytes in [false, true] {
            let store = CarRouteProbeControlStore(root: try directory()), value = try newRun()
            try store.seedAndActivate(value)
            let folder = store.runDirectory(value).appendingPathComponent("Receipts")
            let writer = CarRouteProbeReceiptWriter(run: value, slot: nil, directory: folder,
                maximumCount: useBytes ? 1024 : 2, maximumBytes: useBytes ? 2048 : 4 * 1024 * 1024)
            let finalID = try XCTUnwrap(writer.record(phase: "screenLoaded"))
            let final = folder.appendingPathComponent(finalID.uuidString + ".json")
            let retained = try Data(contentsOf: final)
            let stage = folder.appendingPathComponent(".receipt-" + UUID().uuidString)
            try Data(repeating: 0, count: useBytes ? 2048 : 1).write(to: stage)
            XCTAssertNil(writer.record(phase: "screenClosed"))
            XCTAssertEqual(try Data(contentsOf: final), retained)
            XCTAssertTrue(FileManager.default.fileExists(atPath: stage.path))
            XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: folder.path)
                .filter { $0 != "receipts.lock" }.count, 2)
        }
    }

}
#endif
