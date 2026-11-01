import XCTest
@testable import HearthKit

final class HaClientAuthorizationTests: XCTestCase {
    func testStateGETRechecksAuthorizationAfterBearerAwaitBeforeTransport() async throws {
        let gate = AuthorizationFlag(), transport = RequestCounter()
        let config = HaConfig(baseUrl: "https://fixture.invalid", token: "", entityId: "", refreshToken: "inert")
        let client = HaClient(config, tokenProvider: {
            gate.revoke()
            return "inert"
        }, transport: { request in
            await transport.record()
            return (Data("{}".utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        })
        do {
            _ = try await client.stateJson("climate.room", isAuthorized: { gate.allowed })
            XCTFail("Retired GET must be rejected")
        } catch {}
        let count = await transport.count
        XCTAssertEqual(count, 0)
    }
}
private actor RequestCounter {
    var count = 0
    func record() { count += 1 }
}
private final class AuthorizationFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = true
    var allowed: Bool { lock.lock(); defer { lock.unlock() }; return value }
    func revoke() { lock.lock(); defer { lock.unlock() }; value = false }
}
