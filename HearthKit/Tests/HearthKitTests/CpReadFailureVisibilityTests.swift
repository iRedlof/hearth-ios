import Foundation
import XCTest
@testable import HearthKit

/// Regression coverage for the investigation's findings: a failed ChargePoint read must keep and
/// show its real reason, and a 401 must set `expired` and present sign-in — never the generic text.
final class CpReadFailureVisibilityTests: XCTestCase {
    private static let generic = "Couldn't check · Refresh to retry"

    private func configured() throws -> (CpStateStore, URL) {
        let directory = try CpStoreFixture.directory(self)
        let store = CpStateStore(directory: directory)
        _ = try store.bootstrap(legacy: CpLegacyState(session: CpStoreFixture.session,
            location: CpStoreFixture.location, runWire: "0|0|0|7|0|||"), now: CpStoreFixture.now)
        return (store, directory)
    }

    func test401ReadSetsExpiredAndShowsSignedOutNotGeneric() async throws {
        let (store, directory) = try configured()
        let instant = CpStoreFixture.now
        let runtime = CpOwnedRuntime(store: store, directory: directory,
                                     transport: CpStatusTransport(status: 401), now: { instant })
        let display = try await runtime.refresh(runAuto: false)
        XCTAssertTrue(try store.snapshot(now: instant).session.expired, "A 401 must set expired")
        XCTAssertEqual(display.account, "Signed out")
        XCTAssertNotEqual(display.sub, Self.generic)
    }

    func testNetworkFailureKeepsAndShowsItsReason() async throws {
        let (store, directory) = try configured()
        let instant = CpStoreFixture.now
        let runtime = CpOwnedRuntime(store: store, directory: directory,
            transport: CpStatusTransport(throwing: URLError(.notConnectedToInternet)), now: { instant })
        let display = try await runtime.refresh(runAuto: false)
        XCTAssertTrue(display.stale)
        XCTAssertEqual(display.sub, "No connection · Refresh to retry")
        let failure = try XCTUnwrap(try store.snapshot(now: instant).failure)
        XCTAssertEqual(failure.kind, .network)
    }

    func testStoredFailureShowsItsReasonPerKind() throws {
        let cases: [(CpReadFailureKind, String)] = [
            (.signedOut, "ChargePoint signed you out"),
            (.http(302), "ChargePoint replied 302 · Refresh to retry"),
            (.network, "No connection · Refresh to retry"),
            (.parse, "Couldn't read ChargePoint's reply · Refresh to retry"),
        ]
        for (kind, expectedSub) in cases {
            let (store, _) = try configured()
            let before = try store.snapshot(now: CpStoreFixture.now)
            let owner = try XCTUnwrap(store.beginRead(expected: before.context, now: CpStoreFixture.now))
            let failed = try XCTUnwrap(store.failRead(owner: owner,
                message: cpFailurePresentation(kind).reason, now: CpStoreFixture.now,
                kind: kind, host: "mc.chargepoint.com", status: cpFailureStatusFixture(kind)))
            let display = try failed.displaySnapshot(now: CpStoreFixture.now)
            XCTAssertTrue(display.stale, "\(kind)")
            XCTAssertEqual(display.sub, expectedSub, "\(kind)")
        }
    }

    private func cpFailureStatusFixture(_ kind: CpReadFailureKind) -> Int? {
        switch kind {
        case .signedOut: return 401
        case .refused: return 403
        case let .http(code): return code
        case .network, .parse, .other: return nil
        }
    }
}

// MARK: - Transport that fails the ChargePoint status read deterministically

private final class CpStatusTransport: CpOwnedTransport, @unchecked Sendable {
    private let status: Int
    private let error: URLError?
    init(status: Int = 200, throwing error: URLError? = nil) { self.status = status; self.error = error }
    func prepare(_ request: URLRequest) throws -> any CpPreparedRequest {
        CpStatusPrepared(url: request.url!, status: status, error: error)
    }
}

private struct CpStatusPrepared: CpPreparedRequest {
    let url: URL
    let status: Int
    let error: URLError?
    func start() {}
    func cancel() {}
    func response() async throws -> (Data, HTTPURLResponse) {
        if let error { throw error }
        return (Data("{}".utf8), HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil)!)
    }
}
