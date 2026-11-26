import XCTest
@testable import HearthKit

final class CarReadingsTicketTests: XCTestCase {
    private let time = Date(timeIntervalSince1970: 1_800_000_000)
    private let config = HaConfig(baseUrl: "https://home.example", token: "fixture-private-token", entityId: "")
    private let raw = #"{"found":true,"prefix":"stargate","name":"Same name","s":{"sensor.battery_level":"79","lock.lock":"locked"}}"#

    private func envelope() throws -> CarLiveEnvelope {
        let cache = try carReadingsAfterReply(raw, previous: nil, checkedAt: time)
        let result = CarFetchResult(cache: cache)
        let origin = CarReadingOrigin(requestScope: "account-A", readRevision: "account-A",
            vehiclePrefix: "stargate", status: .readings, configReady: true,
            observedAt: time, displayedObservedAt: time, attemptedAt: time, historical: false)
        return CarLiveEnvelope(snapshot: result.snapshot(now: time), result: result,
            origin: origin, requestReply: .success(raw))
    }

    private func context(scope: String = "account-A", prefix: String = "stargate") throws -> HaStoreSnapshot {
        let cache = try carReadingsAfterReply(raw.replacingOccurrences(of: "stargate", with: prefix),
            previous: nil, checkedAt: time.addingTimeInterval(60))
        let payload = String(data: try JSONEncoder().encode(cache), encoding: .utf8)!
        return HaStoreSnapshot(config: config, scope: scope,
            collectionCaches: ["car": HaCollectionCache(payload: payload, observedAt: cache.checkedAt,
                error: nil, attemptedAt: cache.checkedAt)])
    }

    func testNewerSameVehicleReadAndUnrelatedPickerRevisionKeepTheBoundRoute() throws {
        let ticket = try CarReadingsTicket(envelope: envelope(), issuedAt: time)
        let current = try context()
        let edited = HaStoreSnapshot(config: current.config, scope: current.scope,
            collectionRevision: "unrelated-door-picker", collectionCaches: current.collectionCaches)
        XCTAssertEqual(ticket.validation(in: edited, now: time.addingTimeInterval(61)), .current)
        XCTAssertEqual(ticket.cache?.checkedAt, time)
        XCTAssertEqual(ticket.cache?.current, raw)
    }

    func testSameNameDifferentVehicleCannotValidateTheOldTicket() throws {
        let ticket = try CarReadingsTicket(envelope: envelope(), issuedAt: time)
        XCTAssertEqual(ticket.validation(in: try context(prefix: "other_car"),
            now: time.addingTimeInterval(61)), .configurationChanged)
    }

    func testReturningCredentialsWithNewScopeDoNotRestoreTheOldRoute() throws {
        let ticket = try CarReadingsTicket(envelope: envelope(), issuedAt: time)
        XCTAssertEqual(ticket.validation(in: try context(scope: "account-B"),
            now: time.addingTimeInterval(61)), .configurationChanged)
    }

    func testMissingCurrentStorageOrVehicleIdentityCannotAuthorizeRefresh() throws {
        let ticket = try CarReadingsTicket(envelope: envelope(), issuedAt: time)
        XCTAssertEqual(ticket.validation(in: nil, now: time), .storageUnavailable)
        XCTAssertEqual(ticket.validation(in: HaStoreSnapshot(config: config, scope: "account-A"),
            now: time), .targetUnavailable)
    }

    func testFixedExpiryDoesNotExtendWhenTheSameTicketIsOpenedAgain() throws {
        let ticket = try CarReadingsTicket(envelope: envelope(), issuedAt: time, lifetime: 60)
        XCTAssertEqual(ticket.validation(in: try context(), now: time.addingTimeInterval(59)), .current)
        XCTAssertEqual(ticket.validation(in: try context(), now: time.addingTimeInterval(60)), .expired)
    }

    func testRoundTripRetainsFullTransportFailureWithoutConnectionCredentials() throws {
        let base = try envelope()
        let failed = CarLiveEnvelope(snapshot: base.snapshot,
            result: CarFetchResult(cache: base.result.cache, error: "Sign in again"),
            origin: CarReadingOrigin(requestScope: "account-A", readRevision: "account-A",
                vehiclePrefix: "stargate", status: .authenticationFailure, configReady: true,
                observedAt: time, displayedObservedAt: time, attemptedAt: time, historical: true),
            requestReply: .failure(HaError("Complete authentication failure", code: 401)))
        let ticket = try CarReadingsTicket(envelope: failed, issuedAt: time)
        let data = try JSONEncoder().encode(ticket)
        let restored = try JSONDecoder().decode(CarReadingsTicket.self, from: data)
        XCTAssertEqual(restored, ticket)
        XCTAssertEqual(restored.reply, .failure(message: "Complete authentication failure", code: 401))
        let json = String(decoding: data, as: UTF8.self)
        XCTAssertFalse(json.contains(config.token))
        XCTAssertFalse(json.contains(config.baseUrl))
        XCTAssertEqual(restored.cache?.current, raw)
    }

    func testIncoherentCacheCannotBeBoundToDifferentOrigin() throws {
        let base = try envelope()
        let bad = CarLiveEnvelope(snapshot: base.snapshot,
            result: CarFetchResult(cache: try carReadingsAfterReply(
                raw.replacingOccurrences(of: "stargate", with: "other_car"),
                previous: nil, checkedAt: time)), origin: base.origin, requestReply: base.requestReply)
        XCTAssertThrowsError(try CarReadingsTicket(envelope: bad, issuedAt: time))
    }

    func testSetupTicketDoesNotBecomeAnOperatingVehicleAfterSignIn() throws {
        let result = CarFetchResult(cache: nil, setup: true)
        let setup = CarLiveEnvelope(snapshot: result.snapshot(now: time), result: result,
            origin: CarReadingOrigin(requestScope: "account-A", readRevision: "account-A",
                vehiclePrefix: nil, status: .setup, configReady: false, observedAt: nil,
                displayedObservedAt: nil, attemptedAt: time, historical: false), requestReply: nil)
        let ticket = try CarReadingsTicket(envelope: setup, issuedAt: time)
        XCTAssertEqual(ticket.validation(in: try context(), now: time), .explanationOnly)
    }

    func testChangedStoredObservationCannotValidateTheTicket() throws {
        let ticket = try CarReadingsTicket(envelope: envelope(), issuedAt: time)
        let current = try context()
        let original = try XCTUnwrap(current.collectionCaches["car"])
        let corrupt = HaStoreSnapshot(config: config, scope: current.scope,
            collectionCaches: ["car": HaCollectionCache(payload: original.payload, observedAt: time,
                error: nil, attemptedAt: original.attemptedAt)])
        XCTAssertEqual(ticket.validation(in: corrupt, now: time), .targetUnavailable)
    }

    func testDecoderRejectsFutureVersionAndReattributedRawReading() throws {
        let ticket = try CarReadingsTicket(envelope: envelope(), issuedAt: time)
        let data = try JSONEncoder().encode(ticket)
        var fields = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        fields["version"] = 99
        XCTAssertThrowsError(try JSONDecoder().decode(CarReadingsTicket.self,
            from: JSONSerialization.data(withJSONObject: fields)))
        fields["version"] = 1
        var origin = try XCTUnwrap(fields["origin"] as? [String: Any])
        origin["vehiclePrefix"] = "other_car"
        fields["origin"] = origin
        XCTAssertThrowsError(try JSONDecoder().decode(CarReadingsTicket.self,
            from: JSONSerialization.data(withJSONObject: fields)))
    }

    func testUnprovenHistoricalVehicleCannotBeIncludedInTicket() throws {
        let base = try envelope()
        let cache = CarReadingsCache(current: raw,
            lastGood: raw.replacingOccurrences(of: "stargate", with: "other_car"),
            checkedAt: time, lastGoodCheckedAt: time)
        let bad = CarLiveEnvelope(snapshot: base.snapshot, result: CarFetchResult(cache: cache),
            origin: base.origin, requestReply: base.requestReply)
        XCTAssertThrowsError(try CarReadingsTicket(envelope: bad, issuedAt: time))
    }

    func testUnboundedOrNonFiniteLifetimeCannotBePersisted() throws {
        XCTAssertThrowsError(try CarReadingsTicket(envelope: envelope(), issuedAt: time,
            lifetime: 49 * 60 * 60))
        XCTAssertThrowsError(try CarReadingsTicket(envelope: envelope(), issuedAt: time,
            lifetime: .infinity))
    }

    func testHistoryTicketCannotBorrowCurrentObservationDate() throws {
        let latest = raw.replacingOccurrences(of: #""79""#, with: #""unknown""#)
        let old = try carReadingsAfterReply(raw, previous: nil, checkedAt: time)
        let current = time.addingTimeInterval(30)
        let result = CarFetchResult(cache: try carReadingsAfterReply(latest, previous: old, checkedAt: current))
        let wrong = CarReadingOrigin(requestScope: "account-A", readRevision: "account-A",
            vehiclePrefix: "stargate", status: .history, configReady: true,
            observedAt: current, displayedObservedAt: current, attemptedAt: current, historical: true)
        XCTAssertThrowsError(try CarReadingsTicket(envelope: CarLiveEnvelope(snapshot: result.snapshot(now: current),
            result: result, origin: wrong, requestReply: .success(latest)), issuedAt: current))
    }

    func testCurrentReadingCannotLoseItsProvenDisplayDate() throws {
        let base = try envelope()
        let wrong = CarReadingOrigin(requestScope: "account-A", readRevision: "account-A",
            vehiclePrefix: "stargate", status: .readings, configReady: true,
            observedAt: time, displayedObservedAt: nil, attemptedAt: time, historical: false)
        XCTAssertThrowsError(try CarReadingsTicket(envelope: CarLiveEnvelope(snapshot: base.snapshot,
            result: base.result, origin: wrong, requestReply: base.requestReply), issuedAt: time))
    }

    func testWallClockRollbackPreservesIndependentlyObservedHistory() throws {
        let old = try carReadingsAfterReply(raw, previous: nil, checkedAt: time)
        let checked = time.addingTimeInterval(-60)
        let latest = raw.replacingOccurrences(of: #""79""#, with: #""unknown""#)
        let result = CarFetchResult(cache: try carReadingsAfterReply(latest, previous: old, checkedAt: checked))
        let origin = CarReadingOrigin(requestScope: "account-A", readRevision: "account-A",
            vehiclePrefix: "stargate", status: .history, configReady: true,
            observedAt: checked, displayedObservedAt: time, attemptedAt: checked, historical: true)
        let ticket = try CarReadingsTicket(envelope: CarLiveEnvelope(snapshot: result.snapshot(now: checked),
            result: result, origin: origin, requestReply: .success(latest)), issuedAt: checked)
        XCTAssertEqual(ticket.cache?.lastGoodCheckedAt, time)
        XCTAssertEqual(ticket.origin.observedAt, checked)
        XCTAssertEqual(ticket.origin.displayedObservedAt, time)
    }
}
