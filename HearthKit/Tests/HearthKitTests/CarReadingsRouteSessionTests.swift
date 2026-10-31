import XCTest
@testable import HearthKit

final class CarReadingsRouteSessionTests: XCTestCase {
    private let time = Date(timeIntervalSince1970: 1_800_000_000)
    private let raw = #"{"found":true,"prefix":"stargate","name":"Car","s":{"sensor.battery_level":"79"}}"#
    private let config = HaConfig(baseUrl: "https://home.example", token: "fixture", entityId: "")

    private func ticket(at date: Date, lifetime: TimeInterval = 60) throws -> CarReadingsTicket {
        let result = CarFetchResult(cache: try carReadingsAfterReply(raw, previous: nil, checkedAt: date))
        let origin = CarReadingOrigin(requestScope: "account-A", readRevision: "account-A",
            vehiclePrefix: "stargate", status: .readings, configReady: true, observedAt: date,
            displayedObservedAt: date, attemptedAt: date, historical: false)
        return try CarReadingsTicket(envelope: CarLiveEnvelope(snapshot: result.snapshot(now: date),
            result: result, origin: origin, requestReply: .success(raw)), issuedAt: date, lifetime: lifetime)
    }

    private func context(scope: String = "account-A", prefix: String = "stargate") throws -> HaStoreSnapshot {
        let cache = try carReadingsAfterReply(raw.replacingOccurrences(of: "stargate", with: prefix),
            previous: nil, checkedAt: time)
        return HaStoreSnapshot(config: config, scope: scope, collectionCaches: ["car":
            HaCollectionCache(payload: String(decoding: try JSONEncoder().encode(cache), as: UTF8.self),
                observedAt: time, error: nil, attemptedAt: time)])
    }

    func testDuplicateRefreshAndUnownedCompletionCannotReplaceTheReading() throws {
        let original = try ticket(at: time)
        var session = CarReadingsRouteSession(ticket: original, context: try context(), now: time)
        let claim = try XCTUnwrap(session.beginRefresh(context: try context(), now: time))
        XCTAssertNil(session.beginRefresh(context: try context(), now: time))
        XCTAssertFalse(session.finishRefresh(claim: UUID(), ticket: try ticket(at: time.addingTimeInterval(1)),
            context: try context(), now: time.addingTimeInterval(1)))
        XCTAssertEqual(session.shownTicket, original)
        XCTAssertTrue(session.refreshing)
        XCTAssertTrue(session.finishRefresh(claim: claim, ticket: try ticket(at: time.addingTimeInterval(1)),
            context: try context(), now: time.addingTimeInterval(1)))
        XCTAssertFalse(session.refreshing)
    }

    func testClosePreventsAValidLateReplyFromReplacingOrReopeningTheSession() throws {
        let original = try ticket(at: time)
        var session = CarReadingsRouteSession(ticket: original, context: try context(), now: time)
        let claim = try XCTUnwrap(session.beginRefresh(context: try context(), now: time))
        session.close()
        XCTAssertFalse(session.finishRefresh(claim: claim, ticket: try ticket(at: time.addingTimeInterval(1)),
            context: try context(), now: time.addingTimeInterval(1)))
        XCTAssertEqual(session.shownTicket, original)
        XCTAssertNil(session.beginRefresh(context: try context(), now: time))
    }

    func testAccountOrVehicleChangeDuringRefreshRejectsTheCompletion() throws {
        for context in [try context(scope: "account-B"), try context(prefix: "other_car")] {
            let original = try ticket(at: time)
            var session = CarReadingsRouteSession(ticket: original, context: try self.context(), now: time)
            let claim = try XCTUnwrap(session.beginRefresh(context: try self.context(), now: time))
            XCTAssertFalse(session.finishRefresh(claim: claim, ticket: try ticket(at: time.addingTimeInterval(1)),
                context: context, now: time.addingTimeInterval(1)))
            XCTAssertEqual(session.status, .configurationChanged)
            XCTAssertEqual(session.shownTicket, original)
        }
    }

    func testExpiryWhileRefreshingCannotBeExtendedByALateReply() throws {
        let original = try ticket(at: time, lifetime: 1)
        var session = CarReadingsRouteSession(ticket: original, context: try context(), now: time)
        let claim = try XCTUnwrap(session.beginRefresh(context: try context(), now: time))
        XCTAssertFalse(session.finishRefresh(claim: claim, ticket: try ticket(at: time.addingTimeInterval(2)),
            context: try context(), now: time.addingTimeInterval(2)))
        XCTAssertEqual(session.status, .expired)
        XCTAssertEqual(session.shownTicket, original)
    }

    func testSameTargetSupersededRefreshPreservesAnOperableOriginalReading() throws {
        let original = try ticket(at: time)
        var session = CarReadingsRouteSession(ticket: original, context: try context(), now: time)
        let claim = try XCTUnwrap(session.beginRefresh(context: try context(), now: time))
        XCTAssertFalse(session.finishRefresh(claim: claim, ticket: nil, context: try context(), now: time))
        XCTAssertEqual(session.status, .current)
        XCTAssertEqual(session.shownTicket, original)
        XCTAssertFalse(session.refreshing)
    }
}
