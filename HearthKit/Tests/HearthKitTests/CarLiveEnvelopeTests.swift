import XCTest
@testable import HearthKit

final class CarLiveEnvelopeTests: XCTestCase, @unchecked Sendable {
    private let config = HaConfig(baseUrl: "https://home.example", token: "secret-fixture", entityId: "")
    private let first = Date(timeIntervalSince1970: 1_800_000_000)

    private func store(config: HaConfig? = nil, unconfigured: Bool = false, directory: URL? = nil) -> HaStateStore {
        let directory = directory ?? FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return HaStateStore(directory: directory, initialConfig: unconfigured ? nil : (config ?? self.config),
            initialScope: "account-A")
    }

    private static func reply(_ battery: String, prefixJSON: String = #""stargate""#) -> String {
        """
        {"found":true,"prefix":\(prefixJSON),"name":"Same name","s":{
        "sensor.battery_level":"\(battery)","sensor.charging":"charging",
        "sensor.charger_power":"7.25","sensor.time_to_full_charge":"2027-01-15T09:15:00Z"}}
        """
    }

    // Discovery shares the same bounded ownership budget as the exact route.
    func testExpiredDiscoverySuccessAndFailureDoNotCommitOrRestampExistingReadings() async throws {
        for fails in [false, true] {
            let store = store(), context = try store.snapshot(), first = first
            _ = await fetchOwnedCarEnvelope(store: store, context: context, now: first,
                request: { Self.reply("84") }, observedNow: { first })
            let original = try store.snapshot().collectionCaches["car"]
            let envelope = await fetchOwnedCarEnvelope(store: store, context: context, now: first,
                request: {
                    if fails { throw HaError("Offline") }
                    return Self.reply("23")
                }, observedNow: { first.addingTimeInterval(60) })
            XCTAssertEqual(envelope.origin.status, .obsolete)
            XCTAssertFalse(envelope.origin.isOperating)
            XCTAssertNil(envelope.origin.observedAt)
            XCTAssertEqual(try store.snapshot().collectionCaches["car"], original)
        }
    }

    // Discovery must reject invalid clocks before issuing a persisted owner or requesting HA.
    func testNonfiniteDiscoveryStartClocksDoNotRequestOrChangeRecord() async throws {
        for interval in [Double.nan, .infinity, -.infinity] {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            let store = store(directory: directory), context = try store.snapshot()
            let file = directory.appendingPathComponent("ha-state.json"), original = try Data(contentsOf: file)
            let envelope = await fetchOwnedCarEnvelope(store: store, context: context,
                now: Date(timeIntervalSince1970: interval),
                request: { XCTFail("Invalid start clock requested"); return Self.reply("23") },
                observedNow: { self.first })
            XCTAssertEqual(envelope.origin.status, .storageUnavailable)
            XCTAssertNil(envelope.requestReply)
            XCTAssertEqual(try Data(contentsOf: file), original)
        }
    }

    // Fetch origin must be derived from the same committed raw reply, not a display name or history.
    func testSuccessfulEnvelopeBindsExactScopePrefixAndFullRawReadings() async throws {
        let store = store(), context = try store.snapshot(), finished = first.addingTimeInterval(5)
        let envelope = await fetchOwnedCarEnvelope(store: store, context: context, now: first,
            request: { Self.reply("79", prefixJSON: #"" stargate \n""#) }, observedNow: { finished })
        XCTAssertEqual(envelope.origin.requestScope, "account-A")
        XCTAssertEqual(envelope.origin.readRevision, context.scope)
        XCTAssertEqual(envelope.origin.vehiclePrefix, "stargate")
        XCTAssertEqual(envelope.origin.status, .readings)
        XCTAssertTrue(envelope.origin.isOperating)
        XCTAssertFalse(envelope.origin.historical)
        XCTAssertTrue(envelope.origin.configReady)
        XCTAssertEqual(envelope.origin.observedAt, finished)
        XCTAssertEqual(envelope.origin.displayedObservedAt, finished)
        XCTAssertEqual(envelope.origin.attemptedAt, finished)
        XCTAssertEqual(envelope.result.currentCar?.chargeState, "charging")
        XCTAssertEqual(envelope.result.currentCar?.chargerKw, 7.25)
        XCTAssertEqual(envelope.result.currentCar?.fullAt, Date(timeIntervalSince1970: 1_800_004_500))
        XCTAssertEqual(envelope.result.cache?.current, Self.reply("79", prefixJSON: #"" stargate \n""#))
        let originJSON = String(data: try JSONEncoder().encode(envelope.origin), encoding: .utf8)!
        XCTAssertFalse(originJSON.contains("secret-fixture"))
        XCTAssertFalse(originJSON.contains("home.example"))
    }

    // Genuine same-vehicle history keeps the successful telemetry time, rather than the new check time.
    func testHistoricalEnvelopeKeepsCurrentIdentityAndOriginalTelemetryTime() async throws {
        let store = store(), context = try store.snapshot(), first = first, later = first.addingTimeInterval(60)
        _ = await fetchOwnedCarEnvelope(store: store, context: context, now: first,
            request: { Self.reply("84") }, observedNow: { first })
        let envelope = await fetchOwnedCarEnvelope(store: store, context: try store.snapshot(), now: later,
            request: { Self.reply("unknown") }, observedNow: { later })
        XCTAssertEqual(envelope.snapshot.battery, 84)
        XCTAssertEqual(envelope.origin.vehiclePrefix, "stargate")
        XCTAssertEqual(envelope.origin.status, .history)
        XCTAssertTrue(envelope.origin.historical)
        XCTAssertFalse(envelope.origin.isOperating)
        XCTAssertEqual(envelope.origin.observedAt, later)
        XCTAssertEqual(envelope.origin.displayedObservedAt, first)
        XCTAssertNil(envelope.result.currentCar?.battery)
        XCTAssertEqual(envelope.result.shownCar?.car.battery, 84)
    }

    // Successful anonymous/no-car responses must retire history rather than inherit an older origin.
    func testUnknownAndDifferentCurrentVehicleNeverBorrowPreviousIdentityOrHistory() async throws {
        for prefix in [#""other""#, #""""#, #"" \n ""#, "null", "123", #""unknown""#] {
            let store = store(), context = try store.snapshot(), first = first, later = first.addingTimeInterval(60)
            _ = await fetchOwnedCarEnvelope(store: store, context: context, now: first,
                request: { Self.reply("84") }, observedNow: { first })
            let envelope = await fetchOwnedCarEnvelope(store: store, context: try store.snapshot(), now: later,
                request: { Self.reply("unknown", prefixJSON: prefix) }, observedNow: { later })
            XCTAssertNil(envelope.snapshot.battery, prefix)
            XCTAssertNil(envelope.result.cache?.lastGood, prefix)
            XCTAssertFalse(envelope.origin.historical, prefix)
            XCTAssertEqual(envelope.origin.vehiclePrefix, prefix == #""other""# ? "other" : nil, prefix)
            XCTAssertEqual(envelope.origin.status, prefix == #""other""# ? .noReading : .unidentified, prefix)
        }
    }

    // A no-car reply wins over retained vehicle data, even when it includes a stray prefix.
    func testNoCarEnvelopeHasNoVehicleAttribution() async throws {
        let store = store(), context = try store.snapshot(), first = first
        _ = await fetchOwnedCarEnvelope(store: store, context: context, now: first,
            request: { Self.reply("84") }, observedNow: { first })
        let envelope = await fetchOwnedCarEnvelope(store: store, context: try store.snapshot(), now: first,
            request: { #"{"found":false,"prefix":"stargate"}"# }, observedNow: { first })
        XCTAssertEqual(envelope.origin.status, .noCar)
        XCTAssertNil(envelope.origin.vehiclePrefix)
        XCTAssertFalse(envelope.origin.isOperating)
        XCTAssertNil(envelope.result.currentCar)
        XCTAssertNil(envelope.result.shownCar)
        XCTAssertEqual(envelope.snapshot.chargeLine, "No car found")
    }

    // Failed authentication is distinguished at the request boundary, without inventing a fresh reading.
    func testFailedEnvelopeRetainsObservationAndStructuredAuthFailure() async throws {
        let store = store(), context = try store.snapshot(), first = first, later = first.addingTimeInterval(60)
        _ = await fetchOwnedCarEnvelope(store: store, context: context, now: first,
            request: { Self.reply("84") }, observedNow: { first })
        let envelope = await fetchOwnedCarEnvelope(store: store, context: try store.snapshot(), now: later,
            request: { throw HaError("Sign-in rejected: check the token", code: 401) }, observedNow: { later })
        XCTAssertEqual(envelope.origin.status, .authenticationFailure)
        XCTAssertEqual(envelope.origin.vehiclePrefix, "stargate")
        XCTAssertTrue(envelope.origin.historical)
        XCTAssertFalse(envelope.origin.isOperating)
        XCTAssertEqual(envelope.origin.observedAt, first)
        XCTAssertEqual(envelope.origin.displayedObservedAt, first)
        XCTAssertEqual(envelope.origin.attemptedAt, later)
        XCTAssertEqual(envelope.requestReply, .failure(HaError("Sign-in rejected: check the token", code: 401)))
        XCTAssertTrue(envelope.snapshot.needsSignIn)
        XCTAssertEqual(envelope.snapshot.battery, 84)
    }

    // A generic HA 401 must still offer sign-in recovery, without losing the original error code.
    func testAuthenticationStatusDoesNotDependOnServerMessageWording() async throws {
        let store = store(), context = try store.snapshot(), first = first
        let envelope = await fetchOwnedCarEnvelope(store: store, context: context, now: first,
            request: { throw HaError("Unauthorized", code: 401) }, observedNow: { first })
        XCTAssertEqual(envelope.origin.status, .authenticationFailure)
        XCTAssertTrue(envelope.snapshot.needsSignIn)
        XCTAssertTrue(envelope.snapshot.needsSettings)
        XCTAssertEqual(envelope.snapshot.chargeLine, "Sign in again")
        XCTAssertEqual(envelope.requestReply, .failure(HaError("Unauthorized", code: 401)))
    }

    // A configured account with no prior response must not gain a vehicle ID from an error or sample.
    func testFirstFailureHasNoInventedVehicleOrObservation() async throws {
        let store = store(), context = try store.snapshot(), first = first
        let envelope = await fetchOwnedCarEnvelope(store: store, context: context, now: first,
            request: { throw URLError(.notConnectedToInternet) }, observedNow: { first })
        XCTAssertEqual(envelope.origin.status, .failed)
        XCTAssertNil(envelope.origin.vehiclePrefix)
        XCTAssertNil(envelope.origin.observedAt)
        XCTAssertNil(envelope.origin.displayedObservedAt)
        XCTAssertFalse(envelope.origin.historical)
        XCTAssertFalse(envelope.origin.isOperating)
        XCTAssertNil(envelope.snapshot.battery)
        XCTAssertEqual(envelope.snapshot.error, "Can't reach Home Assistant")
    }

    // A delayed response must format time-sensitive charge information at completion, not request start.
    func testDelayedResponseDoesNotShowAlreadyElapsedChargeETA() async throws {
        let store = store(), context = try store.snapshot(), first = first
        let finished = first.addingTimeInterval(30)
        let envelope = await fetchOwnedCarEnvelope(store: store, context: context, now: first,
            request: { Self.reply("79").replacingOccurrences(of: "2027-01-15T09:15:00Z", with: "2027-01-15T08:00:20Z") },
            observedNow: { finished })
        XCTAssertEqual(envelope.origin.observedAt, finished)
        XCTAssertFalse(envelope.snapshot.chargeLine.hasPrefix("Full by "))
        XCTAssertTrue(envelope.snapshot.chargeLine.hasPrefix("Charging"))
    }

    // An identified integration with no battery or retained telemetry is a typed no-reading context.
    func testIdentifiedUnknownTelemetryDoesNotClaimOperatingReadings() async throws {
        let store = store(), context = try store.snapshot(), first = first
        let envelope = await fetchOwnedCarEnvelope(store: store, context: context, now: first,
            request: { Self.reply("unknown") }, observedNow: { first })
        XCTAssertEqual(envelope.origin.status, .noReading)
        XCTAssertEqual(envelope.origin.vehiclePrefix, "stargate")
        XCTAssertFalse(envelope.origin.isOperating)
        XCTAssertFalse(envelope.origin.historical)
        XCTAssertNil(envelope.snapshot.battery)
        XCTAssertEqual(envelope.origin.observedAt, first)
    }

    // Cancellation after an uncooperative transport returns keeps raw evidence, but commits no fresh reading.
    func testCancelledSuccessfulTransportKeepsRawReplyAndFailsClosed() async throws {
        let store = store(), context = try store.snapshot(), first = first
        let gate = SuspendedCarReply()
        let task = Task {
            await fetchOwnedCarEnvelope(store: store, context: context, now: first,
                request: { try await gate.request() }, observedNow: { first })
        }
        await gate.waitUntilRequested()
        task.cancel()
        await gate.reply(Self.reply("84"))
        let envelope = await task.value
        XCTAssertEqual(envelope.origin.status, .failed)
        XCTAssertFalse(envelope.origin.isOperating)
        XCTAssertNil(envelope.origin.observedAt)
        XCTAssertNil(envelope.snapshot.battery)
        XCTAssertEqual(envelope.snapshot.error, "Refresh interrupted")
        XCTAssertEqual(envelope.requestReply, .success(Self.reply("84")))
    }

    // A corrupt shared record after transport returns cannot turn uncommitted raw data into an operating origin.
    func testStorageFailureAfterReplyKeepsCapturedOriginNonOperating() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = store(directory: directory), context = try store.snapshot(), first = first
        let envelope = await fetchOwnedCarEnvelope(store: store, context: context, now: first,
            request: {
                try Data("corrupt store".utf8).write(to: directory.appendingPathComponent("ha-state.json"))
                return Self.reply("84")
            }, observedNow: { first })
        XCTAssertEqual(envelope.origin.status, .storageUnavailable)
        XCTAssertEqual(envelope.origin.requestScope, "account-A")
        XCTAssertFalse(envelope.origin.isOperating)
        XCTAssertNil(envelope.origin.vehiclePrefix)
        XCTAssertNil(envelope.origin.observedAt)
        XCTAssertNil(envelope.result.cache)
        XCTAssertNil(envelope.snapshot.battery)
        XCTAssertEqual(envelope.requestReply, .success(Self.reply("84")))
        XCTAssertThrowsError(try store.snapshot())
    }

    // Setup navigation retains the captured unconfigured scope and performs no network request.
    func testSetupEnvelopeIsNonOperatingAndDoesNotRequest() async throws {
        let store = store(unconfigured: true), context = try store.snapshot(), first = first
        let envelope = await fetchOwnedCarEnvelope(store: store, context: context, now: first,
            request: { XCTFail("Setup must not request car data"); return Self.reply("84") },
            observedNow: { first })
        XCTAssertEqual(envelope.origin.requestScope, "account-A")
        XCTAssertEqual(envelope.origin.status, .setup)
        XCTAssertFalse(envelope.origin.configReady)
        XCTAssertFalse(envelope.origin.isOperating)
        XCTAssertTrue(envelope.snapshot.needsSettings)
        XCTAssertNil(envelope.requestReply)
    }

    // A replaced account after actual suspension must never rebind the former reply to current credentials.
    func testSuspendedOldAccountReplyReturnsObsoleteOriginWithoutBorrowingReplacementReadings() async throws {
        let store = store(), old = try store.snapshot(), first = first
        let gate = SuspendedCarReply()
        let task = Task {
            await fetchOwnedCarEnvelope(store: store, context: old, now: first,
                request: { try await gate.request() }, observedNow: { first })
        }
        await gate.waitUntilRequested()
        var replacement = config; replacement.token = "replacement-account"
        let current = try store.saveConfig(replacement)
        _ = await fetchOwnedCarEnvelope(store: store, context: current, now: first,
            request: { Self.reply("23", prefixJSON: #""new-car""#) }, observedNow: { first })
        await gate.reply(Self.reply("84"))
        let envelope = await task.value
        XCTAssertEqual(envelope.origin.requestScope, old.scope)
        XCTAssertEqual(envelope.origin.status, .obsolete)
        XCTAssertFalse(envelope.origin.isOperating)
        XCTAssertNil(envelope.origin.vehiclePrefix)
        XCTAssertNil(envelope.snapshot.battery)
        XCTAssertEqual(envelope.requestReply, .success(Self.reply("84")))
        let displayed = envelope.presentationSnapshot(currentContext: try store.snapshot(), now: first)
        XCTAssertEqual(displayed.battery, 23)
        XCTAssertNil(displayed.error)
        XCTAssertEqual(envelope.origin.requestScope, old.scope)
        XCTAssertEqual(envelope.origin.status, .obsolete)
        let committed = try XCTUnwrap(store.snapshot().collectionCaches["car"]?.payload)
        let cache = try JSONDecoder().decode(CarReadingsCache.self, from: Data(committed.utf8))
        XCTAssertEqual(carReplyIdentity(cache.current)?.vehiclePrefix, "new-car")
        XCTAssertEqual(CarFetchResult(cache: cache).snapshot(now: first).battery, 23)
    }

    // A newer refresh owns completion; the older envelope cannot claim the newer reply as its own.
    func testSupersededReadReturnsObsoleteWithoutAdoptingNewerEnvelope() async throws {
        let store = store(), context = try store.snapshot(), first = first
        let gate = SuspendedCarReply()
        let task = Task {
            await fetchOwnedCarEnvelope(store: store, context: context, now: first,
                request: { try await gate.request() }, observedNow: { first })
        }
        await gate.waitUntilRequested()
        let newer = await fetchOwnedCarEnvelope(store: store, context: context, now: first,
            request: { Self.reply("77") }, observedNow: { first })
        await gate.reply(Self.reply("84"))
        let older = await task.value
        XCTAssertEqual(newer.origin.status, .readings)
        XCTAssertEqual(newer.snapshot.battery, 77)
        XCTAssertEqual(older.origin.status, .obsolete)
        XCTAssertFalse(older.origin.isOperating)
        XCTAssertNil(older.snapshot.battery)
        XCTAssertEqual(older.requestReply, .success(Self.reply("84")))
        let displayed = older.presentationSnapshot(currentContext: try store.snapshot(), now: first)
        XCTAssertEqual(displayed.battery, 77)
        XCTAssertNil(displayed.error)
        XCTAssertEqual(older.origin.status, .obsolete)
    }
}

private actor SuspendedCarReply {
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
