import XCTest
@testable import HearthKit

final class CarExactRouteTests: XCTestCase, @unchecked Sendable {
    private let config = HaConfig(baseUrl: "https://home.example", token: "route-fixture", entityId: "")
    private let first = Date(timeIntervalSince1970: 1_800_000_000)

    private func store(directory: URL? = nil) -> HaStateStore {
        let directory = directory ?? FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return HaStateStore(directory: directory, initialConfig: config, initialScope: "account-A")
    }

    private static func reply(_ battery: String, prefix: String = "stargate") -> String {
        """
        {"found":true,"prefix":"\(prefix)","name":"Same car name","s":{
        "sensor.battery_level":"\(battery)","sensor.battery_range":"205",
        "sensor.charging":"charging","sensor.charger_power":"7.25",
        "sensor.time_to_full_charge":"2027-01-15T09:15:00Z",
        "lock.lock":"locked","switch.sentry_mode":"on"}}
        """
    }

    private func seed(_ store: HaStateStore, battery: String = "84", prefix: String = "stargate") async throws -> HaStoreSnapshot {
        let context = try store.snapshot(), first = first
        _ = await fetchOwnedCarEnvelope(store: store, context: context, now: first,
            request: { Self.reply(battery, prefix: prefix) }, observedNow: { first })
        return try store.snapshot()
    }

    // The ordinary auto-discovery request is the existing route hazard: a successful response
    // for a same-name second vehicle must not become this already-bound route or its global cache.
    func testRouteRefreshRejectsDifferentVehicleWithoutReplacingBoundCache() async throws {
        let store = store(), context = try await seed(store), later = first.addingTimeInterval(60)
        let original = context.collectionCaches["car"]
        let envelope = await fetchOwnedCarRouteEnvelope(store: store, context: context,
            expectedVehiclePrefix: "stargate", now: later,
            request: { Self.reply("23", prefix: "other_vehicle") }, observedNow: { later })
        XCTAssertFalse(envelope.origin.isOperating)
        XCTAssertEqual(envelope.origin.vehiclePrefix, "stargate")
        XCTAssertEqual(envelope.snapshot.battery, 84)
        XCTAssertEqual(try store.snapshot().collectionCaches["car"]?.payload, original?.payload)
        XCTAssertEqual(try store.snapshot().collectionCaches["car"]?.observedAt, first)
    }

    // Same account and display name do not authorize an old route after discovery selects another car.
    func testOldRouteCannotReclaimReplacementVehicleCache() async throws {
        let store = store(), old = try await seed(store)
        let replacement = try await seed(store, battery: "23", prefix: "other_vehicle")
        let envelope = await fetchOwnedCarRouteEnvelope(store: store, context: old,
            expectedVehiclePrefix: "stargate", now: first,
            request: { Self.reply("84") }, observedNow: { self.first })
        XCTAssertEqual(envelope.origin.status, .obsolete)
        XCTAssertNil(envelope.result.cache)
        XCTAssertNil(envelope.snapshot.battery)
        XCTAssertEqual(try store.snapshot().collectionCaches["car"], replacement.collectionCaches["car"])
    }

    // The exact route accepts whitespace-normalized IDs and attributes the actual completion time.
    func testExactSuccessfulRefreshKeepsTargetAndCompletionObservation() async throws {
        let store = store(), context = try await seed(store), later = first.addingTimeInterval(60)
        let envelope = await fetchOwnedCarRouteEnvelope(store: store, context: context,
            expectedVehiclePrefix: " \nstargate\t ", now: first,
            request: { Self.reply("77", prefix: " stargate ") }, observedNow: { later })
        XCTAssertTrue(envelope.origin.isOperating)
        XCTAssertEqual(envelope.origin.requestScope, "account-A")
        XCTAssertEqual(envelope.origin.vehiclePrefix, "stargate")
        XCTAssertEqual(envelope.origin.observedAt, later)
        XCTAssertEqual(envelope.origin.displayedObservedAt, later)
        XCTAssertEqual(envelope.origin.attemptedAt, later)
        XCTAssertEqual(envelope.snapshot.battery, 77)
        XCTAssertEqual(envelope.result.cache?.current, Self.reply("77", prefix: " stargate "))
        XCTAssertNil(try store.snapshot().collectionCaches["car"]?.error)
    }

    // Unknown telemetry from the verified car may retain its history, with the history's own date.
    func testExactUnknownBatteryRetainsOnlySameVehicleHistoryAndItsDate() async throws {
        let store = store(), context = try await seed(store), later = first.addingTimeInterval(60)
        let envelope = await fetchOwnedCarRouteEnvelope(store: store, context: context,
            expectedVehiclePrefix: "stargate", now: later,
            request: { Self.reply("unknown") }, observedNow: { later })
        XCTAssertEqual(envelope.origin.status, .history)
        XCTAssertTrue(envelope.origin.historical)
        XCTAssertFalse(envelope.origin.isOperating)
        XCTAssertEqual(envelope.snapshot.battery, 84)
        XCTAssertEqual(envelope.origin.observedAt, later)
        XCTAssertEqual(envelope.origin.displayedObservedAt, first)
        XCTAssertEqual(envelope.result.cache?.lastGoodCheckedAt, first)
        XCTAssertNil(envelope.result.currentCar?.battery)
    }

    // Successful HTTP transport does not make no-car, unidentified or malformed data safe to commit.
    func testUnattributedRepliesSettleAsFailureWithoutErasingBoundHistory() async throws {
        let cases = [
            #"{"found":false,"prefix":"stargate"}"#,
            #"{"found":true,"prefix":"","s":{"sensor.battery_level":"23"}}"#,
            #"{"found":true,"prefix":null,"s":{"sensor.battery_level":"23"}}"#,
            #"{"found":true,"prefix":123,"s":{"sensor.battery_level":"23"}}"#,
            #"{"found":true,"prefix":"unknown","s":{"sensor.battery_level":"23"}}"#,
            #"{"found":true,"prefix":"stargate"}"#,
            "not JSON"
        ]
        for raw in cases {
            let store = store(), context = try await seed(store), later = first.addingTimeInterval(60)
            let envelope = await fetchOwnedCarRouteEnvelope(store: store, context: context,
                expectedVehiclePrefix: "stargate", now: later, request: { raw }, observedNow: { later })
            XCTAssertEqual(envelope.origin.status, .failed, raw)
            XCTAssertTrue(envelope.origin.historical, raw)
            XCTAssertFalse(envelope.origin.isOperating, raw)
            XCTAssertEqual(envelope.origin.vehiclePrefix, "stargate", raw)
            XCTAssertEqual(envelope.snapshot.battery, 84, raw)
            XCTAssertEqual(envelope.origin.observedAt, first, raw)
            XCTAssertEqual(envelope.origin.displayedObservedAt, first, raw)
            XCTAssertEqual(envelope.origin.attemptedAt, later, raw)
            XCTAssertEqual(envelope.requestReply, .success(raw), raw)
            let after = try store.snapshot()
            XCTAssertEqual(after.collectionCaches["car"]?.payload, context.collectionCaches["car"]?.payload, raw)
            XCTAssertNotNil(after.collectionCaches["car"]?.error, raw)
            XCTAssertNotNil(try store.beginCarRouteRead(expectedScope: context.scope,
                expectedVehiclePrefix: "stargate"), raw)
        }
    }

    // Authentication errors are preserved with their code and do not stamp historical telemetry anew.
    func testExactAuthenticationFailureRetainsSameTargetAndObservation() async throws {
        let store = store(), context = try await seed(store), later = first.addingTimeInterval(60)
        let envelope = await fetchOwnedCarRouteEnvelope(store: store, context: context,
            expectedVehiclePrefix: "stargate", now: later,
            request: { throw HaError("Unauthorized", code: 401) }, observedNow: { later })
        XCTAssertEqual(envelope.origin.status, .authenticationFailure)
        XCTAssertEqual(envelope.origin.vehiclePrefix, "stargate")
        XCTAssertTrue(envelope.origin.historical)
        XCTAssertEqual(envelope.origin.observedAt, first)
        XCTAssertEqual(envelope.snapshot.battery, 84)
        XCTAssertTrue(envelope.snapshot.needsSignIn)
        XCTAssertEqual(envelope.requestReply, .failure(HaError("Unauthorized", code: 401)))
    }

    // Invalid IDs must be refused before network or a read claim; they cannot form entity/template code.
    func testUnsafeOrPrefixlessRoutesNeverRequestOrChangeGlobalCache() async throws {
        for prefix in ["", " \n ", "unknown", "unavailable", "none", "Stargate", "stargate.lock",
                       "stargate/other", "stargate-other", "x' }}{{ states('sensor.secret') }}", "véhicule"] {
            let store = store(), context = try await seed(store)
            XCTAssertThrowsError(try carTargetedTemplate(vehiclePrefix: prefix), prefix)
            let envelope = await fetchOwnedCarRouteEnvelope(store: store, context: context,
                expectedVehiclePrefix: prefix, now: first,
                request: { XCTFail("Invalid route requested"); return Self.reply("23") },
                observedNow: { self.first })
            XCTAssertEqual(envelope.origin.status, .unidentified, prefix)
            XCTAssertNil(envelope.result.cache, prefix)
            XCTAssertNil(envelope.requestReply, prefix)
            XCTAssertEqual(try store.snapshot().collectionCaches["car"], context.collectionCaches["car"], prefix)
            XCTAssertNotNil(try store.beginCarRouteRead(expectedScope: context.scope,
                expectedVehiclePrefix: "stargate"), prefix)
        }
    }

    // The locked route context check must not treat an absent or anonymous discovery as the ticket's car.
    func testRouteContextRequiresActualCoherentMatchingCurrentVehicle() async throws {
        let store = store(), empty = try store.snapshot()
        XCTAssertNil(try store.carRouteContext(expectedScope: empty.scope, expectedVehiclePrefix: "stargate"))
        let context = try await seed(store)
        XCTAssertNotNil(try store.carRouteContext(expectedScope: context.scope, expectedVehiclePrefix: " stargate "))
        XCTAssertNil(try store.carRouteContext(expectedScope: "other-scope", expectedVehiclePrefix: "stargate"))
        XCTAssertNil(try store.carRouteContext(expectedScope: context.scope, expectedVehiclePrefix: "other_vehicle"))
        XCTAssertNil(try store.carRouteContext(expectedScope: context.scope, expectedVehiclePrefix: "bad/prefix"))
        let first = first
        _ = await fetchOwnedCarEnvelope(store: store, context: context, now: first,
            request: { #"{"found":false}"# }, observedNow: { first })
        XCTAssertNil(try store.carRouteContext(expectedScope: context.scope, expectedVehiclePrefix: "stargate"))
    }

    // A stale account context cannot begin a request even if it once held the same target and name.
    func testChangedAccountRefusesBeforeTransportAndKeepsReplacementCache() async throws {
        let store = store(), old = try await seed(store)
        var replacement = config; replacement.token = "replacement-fixture"
        _ = try store.saveConfig(replacement)
        let current = try await seed(store, battery: "23", prefix: "other_vehicle")
        let envelope = await fetchOwnedCarRouteEnvelope(store: store, context: old,
            expectedVehiclePrefix: "stargate", now: first,
            request: { XCTFail("Old account requested"); return Self.reply("84") },
            observedNow: { self.first })
        XCTAssertEqual(envelope.origin.status, .obsolete)
        XCTAssertEqual(envelope.origin.requestScope, old.scope)
        XCTAssertNil(envelope.result.cache)
        XCTAssertNil(envelope.requestReply)
        XCTAssertEqual(try store.snapshot().collectionCaches["car"], current.collectionCaches["car"])
    }

    // Actual suspension allows another process/account generation to replace the target before reply.
    func testChangedAccountDuringAwaitRejectsLateRouteWithoutBorrowingNewCache() async throws {
        let store = store(), context = try await seed(store), first = first
        let gate = ExactCarReplyGate()
        let task = Task {
            await fetchOwnedCarRouteEnvelope(store: store, context: context,
                expectedVehiclePrefix: "stargate", now: first,
                request: { try await gate.request() }, observedNow: { first })
        }
        await gate.waitUntilRequested()
        _ = try store.saveConfig(nil)
        _ = try store.saveConfig(config)
        let current = try await seed(store, battery: "23", prefix: "other_vehicle")
        await gate.reply(Self.reply("84"))
        let envelope = await task.value
        XCTAssertEqual(envelope.origin.status, .obsolete)
        XCTAssertEqual(envelope.origin.requestScope, context.scope)
        XCTAssertNil(envelope.result.cache)
        XCTAssertNil(envelope.snapshot.battery)
        XCTAssertEqual(envelope.requestReply, .success(Self.reply("84")))
        XCTAssertEqual(try store.snapshot().collectionCaches["car"], current.collectionCaches["car"])
    }

    // Same-account discovery may select another car; an older route cannot undo that selected cache.
    func testDifferentVehicleDiscoveryDuringAwaitRejectsLateRoute() async throws {
        let store = store(), context = try await seed(store), first = first
        let gate = ExactCarReplyGate()
        let task = Task {
            await fetchOwnedCarRouteEnvelope(store: store, context: context,
                expectedVehiclePrefix: "stargate", now: first,
                request: { try await gate.request() }, observedNow: { first })
        }
        await gate.waitUntilRequested()
        let current = try await seed(store, battery: "23", prefix: "other_vehicle")
        await gate.reply(Self.reply("84"))
        let envelope = await task.value
        XCTAssertEqual(envelope.origin.status, .obsolete)
        XCTAssertNil(envelope.result.cache)
        XCTAssertNil(envelope.origin.vehiclePrefix)
        XCTAssertEqual(try store.snapshot().collectionCaches["car"], current.collectionCaches["car"])
    }

    // A newer same-car refresh supersedes the old read, but that is not an account/vehicle change.
    func testSameTargetDiscoverySupersedesRouteWithoutMislabelingAccountChange() async throws {
        let store = store(), context = try await seed(store), first = first
        let gate = ExactCarReplyGate()
        let task = Task {
            await fetchOwnedCarRouteEnvelope(store: store, context: context,
                expectedVehiclePrefix: "stargate", now: first,
                request: { try await gate.request() }, observedNow: { first })
        }
        await gate.waitUntilRequested()
        let current = try await seed(store, battery: "77")
        await gate.reply(Self.reply("84"))
        let envelope = await task.value
        XCTAssertEqual(envelope.origin.status, .obsolete)
        XCTAssertNil(envelope.result.cache)
        XCTAssertTrue(envelope.snapshot.error?.contains("superseded") == true)
        XCTAssertFalse(envelope.snapshot.error?.contains("Configuration changed") == true)
        XCTAssertEqual(try store.snapshot().collectionCaches["car"], current.collectionCaches["car"])
    }

    // A route cannot steal ownership while widget discovery is in flight, even for today's same prefix.
    func testPendingDiscoveryIsNotDisplacedByRoute() async throws {
        let store = store(), context = try await seed(store), first = first
        let gate = ExactCarReplyGate()
        let discovery = Task {
            await fetchOwnedCarEnvelope(store: store, context: context, now: first,
                request: { try await gate.request() }, observedNow: { first })
        }
        await gate.waitUntilRequested()
        let envelope = await fetchOwnedCarRouteEnvelope(store: store, context: context,
            expectedVehiclePrefix: "stargate", now: first,
            request: { XCTFail("Competing route requested"); return Self.reply("84") }, observedNow: { first })
        XCTAssertEqual(envelope.origin.status, .obsolete)
        XCTAssertNil(envelope.requestReply)
        XCTAssertTrue(envelope.snapshot.error?.contains("in progress") == true)
        await gate.reply(Self.reply("77"))
        let completed = await discovery.value
        XCTAssertTrue(completed.origin.isOperating)
        XCTAssertEqual(completed.snapshot.battery, 77)
    }

    // App and extension stores share the sidecar lock and cannot independently own two route reads.
    func testIndependentStoreInstancesRejectDuplicateAndConsumeCompletionOnce() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let app = store(directory: directory), context = try await seed(app)
        let widget = HaStateStore(directory: directory)
        let owner = try XCTUnwrap(app.beginCarRouteRead(expectedScope: context.scope, expectedVehiclePrefix: "stargate"))
        XCTAssertNil(try widget.beginCarRouteRead(expectedScope: context.scope, expectedVehiclePrefix: "stargate"))
        let finished = try XCTUnwrap(widget.mergeCarRouteRead(owner, reply: .success(Self.reply("77")), now: first))
        XCTAssertEqual(try app.snapshot().collectionCaches["car"], finished.collectionCaches["car"])
        XCTAssertNil(try app.mergeCarRouteRead(owner, reply: .success(Self.reply("23")),
            now: first.addingTimeInterval(60)))
        XCTAssertEqual(try widget.snapshot().collectionCaches["car"], finished.collectionCaches["car"])
        XCTAssertNotNil(try widget.beginCarRouteRead(expectedScope: context.scope, expectedVehiclePrefix: "stargate"))
    }

    // Generic discovery/failure APIs must not bypass the persisted target claim with a copied read ID.
    func testGenericMergeCannotBypassExactRouteOwner() async throws {
        let store = store(), context = try await seed(store)
        let owner = try XCTUnwrap(store.beginCarRouteRead(expectedScope: context.scope, expectedVehiclePrefix: "stargate"))
        XCTAssertNil(try store.mergeCollection("car", reply: .success(Self.reply("23", prefix: "other_vehicle")),
            expectedScope: context.scope, expectedRevision: context.scope, readID: owner.readID, now: first))
        XCTAssertNil(try store.failCollectionRead(HaCollectionReadOwner(kind: "car", scope: owner.scope,
            revision: owner.scope, readID: owner.readID), error: "Wrong owner", now: first))
        XCTAssertEqual(try store.snapshot().collectionCaches["car"], context.collectionCaches["car"])
        XCTAssertNotNil(try store.mergeCarRouteRead(owner, reply: .success(Self.reply("77")), now: first))
    }

    // An owner must match all persisted components, not merely possess an otherwise valid read ID.
    func testForgedScopeOrPrefixCannotCommitRouteRead() async throws {
        let store = store(), context = try await seed(store)
        let owner = try XCTUnwrap(store.beginCarRouteRead(expectedScope: context.scope, expectedVehiclePrefix: "stargate"))
        let owners = [
            HaCarRouteReadOwner(scope: "other-scope", vehiclePrefix: owner.vehiclePrefix, readID: owner.readID),
            HaCarRouteReadOwner(scope: owner.scope, vehiclePrefix: "other_vehicle", readID: owner.readID),
            HaCarRouteReadOwner(scope: owner.scope, vehiclePrefix: " stargate ", readID: owner.readID),
            HaCarRouteReadOwner(scope: owner.scope, vehiclePrefix: owner.vehiclePrefix, readID: "other-read")
        ]
        for forged in owners {
            XCTAssertNil(try store.mergeCarRouteRead(forged, reply: .success(Self.reply("23")), now: first))
            XCTAssertEqual(try store.snapshot().collectionCaches["car"], context.collectionCaches["car"])
        }
        XCTAssertNotNil(try store.mergeCarRouteRead(owner, reply: .success(Self.reply("77")), now: first))
    }

    // Picker revisions belong to other widgets and cannot invalidate Car's same-account/target claim.
    func testUnrelatedPickerEditsPreserveExactRouteOwnership() async throws {
        let store = store(), context = try await seed(store)
        let owner = try XCTUnwrap(store.beginCarRouteRead(expectedScope: context.scope, expectedVehiclePrefix: "stargate"))
        var edited = config; edited.entityId = "alarm_control_panel.other"
        edited.lockId = "lock.front_door"; edited.doorIdsJson = #"["cover.garage"]"#
        let after = try store.saveConfig(edited)
        XCTAssertEqual(after.scope, context.scope)
        XCTAssertNotEqual(after.collectionRevision, context.collectionRevision)
        XCTAssertNotNil(try store.carRouteContext(expectedScope: context.scope, expectedVehiclePrefix: "stargate"))
        let finished = try XCTUnwrap(store.mergeCarRouteRead(owner, reply: .success(Self.reply("77")), now: first))
        XCTAssertEqual(try decodedCache(finished).current, Self.reply("77"))
    }

    // Auto-adopted doors are unrelated selection changes too; preserve the route's persistent target.
    func testDoorDiscoveryPreservesExactRouteOwnership() async throws {
        let store = store(), context = try await seed(store)
        let owner = try XCTUnwrap(store.beginCarRouteRead(expectedScope: context.scope, expectedVehiclePrefix: "stargate"))
        let doorRead = try XCTUnwrap(store.beginCollectionRead("doors", expectedScope: context.scope,
            expectedRevision: context.collectionRevision))
        _ = try store.adoptDoorDiscovery(["cover.garage"], expectedScope: context.scope,
            expectedRevision: context.collectionRevision, readID: doorRead)
        let finished = try XCTUnwrap(store.mergeCarRouteRead(owner, reply: .success(Self.reply("77")), now: first))
        XCTAssertEqual(try decodedCache(finished).current, Self.reply("77"))
    }

    // Cancellation after an uncooperative reply never turns that data into a fresh observation.
    func testCancelledExactTransportKeepsRawEvidenceButNoFreshTelemetry() async throws {
        let store = store(), context = try await seed(store), first = first
        let gate = ExactCarReplyGate()
        let task = Task {
            await fetchOwnedCarRouteEnvelope(store: store, context: context,
                expectedVehiclePrefix: "stargate", now: first,
                request: { try await gate.request() }, observedNow: { first.addingTimeInterval(60) })
        }
        await gate.waitUntilRequested()
        task.cancel()
        await gate.reply(Self.reply("23"))
        let envelope = await task.value
        XCTAssertEqual(envelope.origin.status, .failed)
        XCTAssertFalse(envelope.origin.isOperating)
        XCTAssertEqual(envelope.snapshot.battery, 84)
        XCTAssertEqual(envelope.origin.observedAt, first)
        XCTAssertEqual(envelope.requestReply, .success(Self.reply("23")))
        XCTAssertTrue(envelope.snapshot.error?.contains("interrupted") == true)
    }

    // A broken shared file cannot lend successful but uncommitted transport data a fresh origin.
    func testStorageCorruptionAfterExactReplyIsNonOperatingAndDoesNotBorrowCapturedCache() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = store(directory: directory), context = try await seed(store), first = first
        let envelope = await fetchOwnedCarRouteEnvelope(store: store, context: context,
            expectedVehiclePrefix: "stargate", now: first,
            request: {
                try Data("broken".utf8).write(to: directory.appendingPathComponent("ha-state.json"))
                return Self.reply("23")
            }, observedNow: { first })
        XCTAssertEqual(envelope.origin.status, .storageUnavailable)
        XCTAssertNil(envelope.result.cache)
        XCTAssertNil(envelope.snapshot.battery)
        XCTAssertFalse(envelope.origin.isOperating)
        XCTAssertEqual(envelope.requestReply, .success(Self.reply("23")))
        XCTAssertThrowsError(try store.snapshot())
    }

    private func decodedCache(_ context: HaStoreSnapshot) throws -> CarReadingsCache {
        let payload = try XCTUnwrap(context.collectionCaches["car"]?.payload)
        return try JSONDecoder().decode(CarReadingsCache.self, from: Data(payload.utf8))
    }
}

private actor ExactCarReplyGate {
    private var continuation: CheckedContinuation<String, any Error>?
    private var startWaiters: [CheckedContinuation<Void, Never>] = []

    func request() async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            for waiter in startWaiters { waiter.resume() }
            startWaiters = []
        }
    }

    func waitUntilRequested() async {
        guard continuation == nil else { return }
        await withCheckedContinuation { startWaiters.append($0) }
    }

    func reply(_ raw: String) {
        continuation?.resume(returning: raw)
        continuation = nil
    }
}
