import Foundation
import XCTest
@testable import HearthKit

final class CpOwnedHTTPTests: XCTestCase {
    private func configured() throws -> (CpStateStore, URL) {
        let directory = try CpStoreFixture.directory(self)
        let store = CpStateStore(directory: directory)
        _ = try store.bootstrap(legacy: CpStoreFixture.legacy, now: CpStoreFixture.now)
        return (store, directory)
    }

    func testPreparedReadCarriesLatestOwnedCookieAndStartsAfterDurableAdmission() async throws {
        let (store, directory) = try configured()
        let instant = CpStoreFixture.now
        let owner = try XCTUnwrap(store.beginRead(expected: store.snapshot(now: instant).context, now: instant))
        let transport = CpHTTPProbe { request in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.value(forHTTPHeaderField: "cp-session-token"), CpStoreFixture.session.token)
            XCTAssertEqual(request.value(forHTTPHeaderField: "Cookie"), "coulomb_sess=\(CpStoreFixture.session.token)")
            let json = try JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as! [String: Any]
            XCTAssertEqual(json["user_id"] as? Int64, CpStoreFixture.session.userId)
        }
        let result = try await CpOwnedHTTP(store: store, directory: directory, transport: transport)
            .send(authority: .read(owner), purpose: .status, now: { instant })
        XCTAssertEqual(result.body, "{}")
        XCTAssertEqual(transport.starts, 1)
        XCTAssertEqual(transport.prepares, 1)
        XCTAssertEqual(try store.snapshot(now: instant).session.token, "rolled")
    }

    func testStaleReadDoesNotPrepareOrStartRequest() async throws {
        let (store, directory) = try configured()
        let instant = CpStoreFixture.now
        let old = try XCTUnwrap(store.beginRead(expected: store.snapshot(now: instant).context, now: instant))
        _ = try store.beginRead(expected: store.snapshot(now: instant).context, now: instant)
        let transport = CpHTTPProbe()
        do {
            _ = try await CpOwnedHTTP(store: store, directory: directory, transport: transport)
                .send(authority: .read(old), purpose: .status, now: { instant })
            XCTFail("Retired read must not dispatch")
        } catch {}
        XCTAssertEqual(transport.prepares, 0)
        XCTAssertEqual(transport.starts, 0)
    }

    func testPreparationEditIsRecheckedBeforeStartAndCancelsSuspendedTask() async throws {
        let (store, directory) = try configured()
        let instant = CpStoreFixture.now
        let snapshot = try store.snapshot(now: instant)
        let owner = try XCTUnwrap(store.beginRead(expected: snapshot.context, now: instant))
        let transport = CpHTTPProbe { _ in
            _ = try store.edit(expected: snapshot.settingsOrigin, edit: .signOut, now: instant)
        }
        do {
            _ = try await CpOwnedHTTP(store: store, directory: directory, transport: transport)
                .send(authority: .read(owner), purpose: .status, now: { instant })
            XCTFail("Edited account must not dispatch")
        } catch {}
        XCTAssertEqual(transport.prepares, 1)
        XCTAssertEqual(transport.starts, 0)
        XCTAssertEqual(transport.cancels, 1)
    }

    func testPermanentGateSerializesIndependentInstancesWithoutLockReplacement() async throws {
        let directory = try CpStoreFixture.directory(self)
        let probe = CpGateProbe()
        try await withThrowingTaskGroup(of: Void.self) { group in
            for _ in 0..<12 {
                group.addTask {
                    try await CpRequestGate(directory: directory).withLock {
                        probe.enter()
                        try await Task.sleep(nanoseconds: 2_000_000)
                        probe.exit()
                    }
                }
            }
            try await group.waitForAll()
        }
        XCTAssertEqual(probe.maximum, 1)
        XCTAssertEqual(probe.count, 12)
        XCTAssertTrue(FileManager.default.fileExists(atPath: directory.appendingPathComponent("cp-request.lock").path))
    }

    func testURLSessionTaskIsInitiallySuspendedAndCanCancelWithoutStarting() throws {
        let prepared = try CpURLSessionTransport().prepare(URLRequest(url: URL(string: "https://example.invalid")!))
        prepared.cancel()
        // No start and no network request: response completion is intentionally not awaited here.
    }

    func testResponseRetiredAfterStartCannotReturnBodyForPublication() async throws {
        let (store, directory) = try configured()
        let instant = CpStoreFixture.now
        let context = try store.snapshot(now: instant)
        let owner = try XCTUnwrap(store.beginRead(expected: context.context, now: instant))
        let transport = CpHTTPProbe(beforeResponse: {
            _ = try store.edit(expected: context.settingsOrigin, edit: .signOut, now: instant)
        })
        do {
            _ = try await CpOwnedHTTP(store: store, directory: directory, transport: transport)
                .send(authority: .read(owner), purpose: .status, now: { instant })
            XCTFail("Retired response must not leave the owned HTTP boundary")
        } catch {}
        XCTAssertEqual(transport.starts, 1)
        XCTAssertFalse(try store.snapshot(now: instant).session.isSignedIn)
    }
}

private final class CpHTTPProbe: CpOwnedTransport, CpPreparedRequest, @unchecked Sendable {
    private let lock = NSLock()
    private var _starts = 0, _prepares = 0, _cancels = 0
    private var url: URL?
    private let check: @Sendable (URLRequest) throws -> Void
    private let beforeResponse: @Sendable () throws -> Void
    init(_ check: @escaping @Sendable (URLRequest) throws -> Void = { _ in },
         beforeResponse: @escaping @Sendable () throws -> Void = {}) {
        self.check = check; self.beforeResponse = beforeResponse
    }
    var starts: Int { lock.withLock { _starts } }
    var prepares: Int { lock.withLock { _prepares } }
    var cancels: Int { lock.withLock { _cancels } }
    func prepare(_ request: URLRequest) throws -> any CpPreparedRequest {
        lock.withLock { _prepares += 1; url = request.url }
        try check(request)
        return self
    }
    func start() { lock.withLock { _starts += 1 } }
    func cancel() { lock.withLock { _cancels += 1 } }
    func response() async throws -> (Data, HTTPURLResponse) {
        try beforeResponse()
        let target = lock.withLock { url! }
        return (Data("{}".utf8), HTTPURLResponse(url: target, statusCode: 200, httpVersion: nil,
            headerFields: ["Set-Cookie": "coulomb_sess=rolled; Path=/"])!)
    }
}

private final class CpGateProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var active = 0, _maximum = 0, _count = 0
    var maximum: Int { lock.withLock { _maximum } }
    var count: Int { lock.withLock { _count } }
    func enter() { lock.withLock { active += 1; _maximum = max(active, _maximum); _count += 1 } }
    func exit() { lock.withLock { active -= 1 } }
}
