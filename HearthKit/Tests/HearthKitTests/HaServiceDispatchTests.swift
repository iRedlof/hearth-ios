import XCTest
@testable import HearthKit

final class HaServiceDispatchTests: XCTestCase {
    private let config = HaConfig(baseUrl: "https://example.invalid", token: "", entityId: "alarm_control_panel.home",
                                  refreshToken: "inert")
    func testRevocationDuringBearerRenewalPreventsServicePost() async throws {
        let origin = HaDispatchOrigin()
        let client = HaClient(config, tokenProvider: {
            origin.revoke()
            return "inert-access-token"
        }, transport: { _ in XCTFail("Revoked after token wait: no POST"); throw HaError("Unexpected dispatch") })
        do {
            try await client.callService(domain: "alarm_control_panel", service: "alarm_disarm",
                entityId: config.entityId, isAuthorized: { origin.current })
            XCTFail("Revoked command must fail before transport")
        } catch let error as HaError { XCTAssertEqual(error.message, "Configuration changed · Refresh to check") }
    }

    func testCancelledBearerWaitPreventsServicePost() async throws {
        let client = HaClient(config, tokenProvider: {
            withUnsafeCurrentTask { $0?.cancel() }
            return "inert-access-token"
        }, transport: { _ in XCTFail("Cancelled request: no POST"); throw HaError("Unexpected dispatch") })
        let task = Task {
            try await client.callService(domain: "lock", service: "unlock", entityId: "lock.front", isAuthorized: { true })
        }
        do { try await task.value; XCTFail("Must propagate cancellation") } catch is CancellationError {}
    }

    func testCurrentCommandSendsOneBoundRequestWithResolvedBearer() async throws {
        let requests = HaDispatchRequests()
        let client = HaClient(config, tokenProvider: { "inert-access-token" }, transport: { request in
            await requests.add(request)
            return (Data("[]".utf8), HTTPURLResponse(url: request.url!, statusCode: 200,
                httpVersion: nil, headerFields: nil)!)
        })
        try await client.callService(domain: "lock", service: "unlock", entityId: "lock.front", isAuthorized: { true })
        let sent = await requests.values
        XCTAssertEqual(sent.count, 1)
        XCTAssertEqual(sent.first?.url?.path, "/api/services/lock/unlock")
        XCTAssertEqual(sent.first?.value(forHTTPHeaderField: "Authorization"), "Bearer inert-access-token")
        let body = try XCTUnwrap(sent.first?.httpBody)
        XCTAssertEqual((try JSONSerialization.jsonObject(with: body) as? [String: String])?["entity_id"], "lock.front")
    }
}

private actor HaDispatchRequests {
    var values: [URLRequest] = []
    func add(_ request: URLRequest) { values.append(request) }
}
private final class HaDispatchOrigin: @unchecked Sendable {
    private let lock = NSLock()
    private var valid = true
    var current: Bool { lock.lock(); defer { lock.unlock() }; return valid }
    func revoke() { lock.lock(); defer { lock.unlock() }; valid = false }
}
