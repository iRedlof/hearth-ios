import Foundation
import XCTest
@testable import HearthKit

/// Reproduces the widget's real sequence (render → further reads → tap) and proves the exact
/// Accept/Leave requests reach the network, using the reply shapes a real account returns.
final class CpActionRequestParityTests: XCTestCase {
    private func configured(armed: Bool = false) throws -> (CpStateStore, URL) {
        let directory = try CpStoreFixture.directory(self)
        let store = CpStateStore(directory: directory)
        _ = try store.bootstrap(legacy: CpLegacyState(session: CpStoreFixture.session,
            location: CpStoreFixture.location, runWire: armed ? "1|0|0|7|0|||" : "0|0|0|7|0|||"), now: CpStoreFixture.now)
        return (store, directory)
    }

    // A waitlist whose stations match the saved location, so the state alone is under test.
    private static let waiting = "{\"user_status\":{\"waitlist\":{\"state\":{\"state\":\"WAITING\",\"regionId\":0},\"stations\":[{\"deviceId\":1},{\"deviceId\":2}]}}}"
    // The same queue after one more charger appears — a genuinely different observed identity.
    private static let waitingChanged = "{\"user_status\":{\"waitlist\":{\"state\":{\"state\":\"WAITING\",\"regionId\":0},\"stations\":[{\"deviceId\":1},{\"deviceId\":2},{\"deviceId\":3}]}}}"
    // A real ACCEPT_PENDING offer shape (deviceId/portNo/token/startTimeUTC/duration present).
    private static let offer = "{\"user_status\":{\"waitlist\":{\"state\":{\"state\":\"ACCEPT_PENDING\",\"currentTimeUTC\":1792372115,\"startTimeUTC\":1792372024,\"deviceId\":1,\"duration\":1200,\"token\":\"T0K3N\",\"portNo\":1,\"regionId\":0},\"stations\":[{\"deviceId\":1},{\"deviceId\":2}]}}}"

    /// THE regression: a button rendered from one read, then a timeline reload (a second identical
    /// read), then the tap. On main the second read rotates the stamp and the tap is a silent no-op
    /// (0 mutations). On this branch the unchanged identity keeps the button valid and Leave is sent.
    func testWidgetSequenceSendsLeaveWhenStateUnchangedAcrossAReload() async throws {
        let (store, directory) = try configured()
        let instant = CpStoreFixture.now
        let transport = CpRecordingTransport(status: Self.waiting, mutationBody: "")   // empty 200 body
        let runtime = CpOwnedRuntime(store: store, directory: directory, transport: transport, now: { instant })
        _ = try await runtime.refresh(runAuto: false)                                  // render, origin A
        let origin = try XCTUnwrap(store.snapshot(now: instant).renderedOrigin)
        _ = try await runtime.refresh(runAuto: false)                                  // timeline reload
        _ = try await runtime.perform(origin: origin, action: .leave)                  // the tap
        XCTAssertEqual(transport.mutations, 1, "Leave must be sent when the waitlist state is unchanged")
        XCTAssertNil(try store.snapshot(now: instant).operation)
        XCTAssertEqual(try store.snapshot(now: instant).lastAction?.outcome, "Left the waitlist")
    }

    /// Seen on a real account (2026-11-27): the offer token differs on EVERY status read while the
    /// offer (charger, port, start, deadline) is the same. A button drawn from one read must still
    /// act after a reload, and the last-second re-read before sending must not call it a new offer.
    func testLeaveAndAcceptAreSentWhenTheOfferTokenIsReissuedOnEveryRead() async throws {
        for action in [CpOwnedAction.leave, .accept] {
            let (store, directory) = try configured()
            let instant = CpStoreFixture.now
            let transport = action == .leave ? CpRecordingTransport(status: Self.offer, mutationBody: "")
                                             : CpRecordingTransport(status: Self.offer)
            transport.reissuesTokenOnEveryRead = true
            let runtime = CpOwnedRuntime(store: store, directory: directory, transport: transport, now: { instant })
            _ = try await runtime.refresh(runAuto: false)                              // widget drawn
            let origin = try XCTUnwrap(store.snapshot(now: instant).renderedOrigin)
            _ = try await runtime.refresh(runAuto: false)                              // timeline reload
            _ = try await runtime.perform(origin: origin, action: action)              // the tap
            XCTAssertEqual(transport.mutations, 1, "\(action) must be sent for the same offer with a re-issued token")
            XCTAssertNil(try store.snapshot(now: instant).ownershipFeedback, "\(action) must not report a changed offer")
        }
    }

    /// The protection still holds: when the state really changed between render and tap, the tap is
    /// refused, nothing is sent, and a visible reason is left behind.
    func testWidgetSequenceRefusesWithReasonWhenStateChanged() async throws {
        let (store, directory) = try configured()
        let instant = CpStoreFixture.now
        let transport = CpRecordingTransport(status: Self.waiting, mutationBody: "")
        let runtime = CpOwnedRuntime(store: store, directory: directory, transport: transport, now: { instant })
        _ = try await runtime.refresh(runAuto: false)
        let origin = try XCTUnwrap(store.snapshot(now: instant).renderedOrigin)
        transport.status = Self.waitingChanged                                         // the queue changed
        _ = try await runtime.refresh(runAuto: false)
        _ = try await runtime.perform(origin: origin, action: .leave)
        XCTAssertEqual(transport.mutations, 0, "A stale tap on a changed queue must not be sent")
        XCTAssertEqual(try store.snapshot(now: instant).ownershipFeedback, .detailsChanged)
    }

    /// A 200 with an empty body (what a real Leave returns) is a success, not a parse failure.
    func testEmptyTwoHundredLeaveBodyIsSuccess() async throws {
        let (store, directory) = try configured()
        let instant = CpStoreFixture.now
        let transport = CpRecordingTransport(status: Self.waiting, mutationBody: "")
        let runtime = CpOwnedRuntime(store: store, directory: directory, transport: transport, now: { instant })
        _ = try await runtime.refresh(runAuto: false)
        let origin = try XCTUnwrap(store.snapshot(now: instant).renderedOrigin)
        _ = try await runtime.perform(origin: origin, action: .leave)
        XCTAssertNil(try store.snapshot(now: instant).ownershipFeedback)
        XCTAssertNil(try store.snapshot(now: instant).operation)
    }

    func testLeaveSendsExactlyTheAndroidRequest() async throws {
        let (store, directory) = try configured()
        let instant = CpStoreFixture.now
        let transport = CpRecordingTransport(status: Self.waiting, mutationBody: "")
        let runtime = CpOwnedRuntime(store: store, directory: directory, transport: transport, now: { instant })
        _ = try await runtime.refresh(runAuto: false)
        _ = try await runtime.perform(origin: XCTUnwrap(store.snapshot(now: instant).renderedOrigin), action: .leave)
        let request = try XCTUnwrap(transport.lastMutation)
        XCTAssertEqual(request.method, "DELETE")
        XCTAssertEqual(request.url, "https://account.chargepoint.com/account/v1/driver/station/waitlist/leave")
        XCTAssertTrue(request.body.isEmpty)
        assertAuthHeaders(request)
    }

    func testAcceptSendsExactlyTheAndroidRequest() async throws {
        let (store, directory) = try configured()
        let instant = CpStoreFixture.now
        let transport = CpRecordingTransport(status: Self.offer)
        let runtime = CpOwnedRuntime(store: store, directory: directory, transport: transport, now: { instant })
        _ = try await runtime.refresh(runAuto: false)
        _ = try await runtime.perform(origin: XCTUnwrap(store.snapshot(now: instant).renderedOrigin), action: .accept)
        let request = try XCTUnwrap(transport.lastMutation)
        XCTAssertEqual(request.method, "POST")
        XCTAssertEqual(request.url, "https://na.chargepoint.com/backend.php/community/acceptV2")
        XCTAssertTrue(request.body.isEmpty)
        XCTAssertEqual(request.headers["Content-Type"], "application/x-www-form-urlencoded")
        assertAuthHeaders(request)
    }

    private func assertAuthHeaders(_ request: CpRecordedRequest) {
        let token = CpStoreFixture.session.token
        XCTAssertEqual(request.headers["Cookie"], "coulomb_sess=\(token)")
        XCTAssertEqual(request.headers["cp-session-token"], token)
        XCTAssertEqual(request.headers["cp-session-type"], "CP_SESSION_TOKEN")
        XCTAssertEqual(request.headers["cp-region"], "NA-US")
        XCTAssertEqual(request.headers["Accept"], "application/json")
    }
}

struct CpRecordedRequest: Sendable {
    let method: String
    let url: String
    let body: String
    let headers: [String: String]
}

private final class CpRecordingTransport: CpOwnedTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var raw: String
    private var reply: String
    private var mutationCount = 0
    private var statusReads = 0
    /// Real ChargePoint behaviour: every status read carries a newly issued offer token.
    var reissuesTokenOnEveryRead = false
    private var recorded: [CpRecordedRequest] = []

    init(status: String, mutationBody: String = "{\"result\":true,\"response\":{\"success\":true}}") {
        raw = status; reply = mutationBody
    }
    var status: String { get { lock.withLock { raw } } set { lock.withLock { raw = newValue } } }
    var mutations: Int { lock.withLock { mutationCount } }
    var lastMutation: CpRecordedRequest? { lock.withLock { recorded.last } }

    func prepare(_ request: URLRequest) throws -> any CpPreparedRequest {
        let path = request.url!.path
        let mutates = path.hasSuffix("/join") || path.contains("V2") || path.hasSuffix("/leave") || path.hasSuffix("/stopSession")
        let body: String
        if mutates { body = reply }
        else if path.contains("/get_notification_detail/") { body = "{\"response\":{}}" }
        else if path.hasSuffix("/inlinestatus") { body = "{\"positionInline\":3}" }
        else {
            let object = request.httpBody.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
            if object?["user_status"] != nil {
                let read = lock.withLock { statusReads += 1; return statusReads }
                body = reissuesTokenOnEveryRead ? status.replacingOccurrences(of: "T0K3N", with: "T0K3N-\(read)") : status
            } else { body = "{}" }
        }
        if mutates {
            lock.withLock {
                recorded.append(CpRecordedRequest(method: request.httpMethod ?? "",
                    url: request.url!.absoluteString,
                    body: request.httpBody.map { String(decoding: $0, as: UTF8.self) } ?? "",
                    headers: request.allHTTPHeaderFields ?? [:]))
            }
        }
        return CpRecordingPrepared(url: request.url!, body: body) { [self] in
            if mutates { lock.withLock { mutationCount += 1 } }
        }
    }
}

private struct CpRecordingPrepared: CpPreparedRequest {
    let url: URL
    let body: String
    let onStart: @Sendable () -> Void
    func start() { onStart() }
    func cancel() {}
    func response() async throws -> (Data, HTTPURLResponse) {
        (Data(body.utf8), HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!)
    }
}
