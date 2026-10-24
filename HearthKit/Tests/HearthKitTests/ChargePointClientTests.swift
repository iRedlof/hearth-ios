import XCTest
@testable import HearthKit

/// Thread-safe capture box (the transport closure is `@Sendable`, so it can't capture test vars directly).
private final class Box: @unchecked Sendable {
    var req: URLRequest?
    var rolled: String?
}

private func resp(_ url: URL, _ body: String, _ status: Int = 200,
                  _ headers: [String: String]? = nil) -> (Data, HTTPURLResponse) {
    (body.data(using: .utf8)!, HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: headers)!)
}

final class ChargePointClientTests: XCTestCase {
    func testUserStatusRequestShape() async throws {
        let box = Box()
        let c = CpClient(token: "tok", userId: 42, transport: { req in
            box.req = req
            return resp(req.url!, #"{"user_status":{}}"#)
        })
        _ = try await c.userStatus()
        let req = try XCTUnwrap(box.req)
        XCTAssertEqual(req.url?.absoluteString, "https://mc.chargepoint.com/map-prod/v2")
        XCTAssertEqual(req.httpMethod, "POST")
        XCTAssertEqual(req.value(forHTTPHeaderField: "cp-session-token"), "tok")
        XCTAssertEqual(req.value(forHTTPHeaderField: "cp-session-type"), "CP_SESSION_TOKEN")
        XCTAssertEqual(req.value(forHTTPHeaderField: "cp-region"), "NA-US")
        XCTAssertEqual(req.value(forHTTPHeaderField: "Cookie"), "coulomb_sess=tok")
        let body = try JSONSerialization.jsonObject(with: req.httpBody!) as! [String: Any]
        XCTAssertEqual(body["user_id"] as? Int, 42)       // user_id must be top level
        XCTAssertNotNil(body["user_status"])
    }

    func testRolledCookieIsPersisted() async throws {
        let box = Box()
        let c = CpClient(token: "old", userId: 1, onToken: { box.rolled = $0 }, transport: { req in
            resp(req.url!, "{}", 200, ["Set-Cookie": "coulomb_sess=NEW123; Path=/; Max-Age=7200"])
        })
        _ = try await c.userStatus()
        XCTAssertEqual(box.rolled, "NEW123")
    }

    func testAcceptIsFormPostToPortal() async throws {
        let box = Box()
        let c = CpClient(token: "t", userId: 1, transport: { req in
            box.req = req
            return resp(req.url!, #"{"result":true}"#)
        })
        try await c.accept()
        let req = try XCTUnwrap(box.req)
        XCTAssertTrue(req.url!.absoluteString.contains("na.chargepoint.com"))
        XCTAssertTrue(req.url!.absoluteString.contains("acceptV2"))
        XCTAssertEqual(req.httpMethod, "POST")
        XCTAssertEqual(req.value(forHTTPHeaderField: "Content-Type"), "application/x-www-form-urlencoded")
    }

    func testSnoozeSendsSeconds() async throws {
        let box = Box()
        let c = CpClient(token: "t", userId: 1, transport: { req in
            box.req = req
            return resp(req.url!, #"{"result":true}"#)
        })
        try await c.snooze(seconds: 3600)
        let req = try XCTUnwrap(box.req)
        XCTAssertTrue(req.url!.absoluteString.contains("snoozeV2"))
        XCTAssertEqual(String(data: req.httpBody ?? Data(), encoding: .utf8), "snoozeTime=3600")
    }

    func test401IsSignedOut() async throws {
        let c = CpClient(token: "t", userId: 1, transport: { req in resp(req.url!, "{}", 401) })
        do { _ = try await c.userStatus(); XCTFail("should throw") }
        catch let e as HaError { XCTAssertEqual(e.code, 401) }
    }
}
