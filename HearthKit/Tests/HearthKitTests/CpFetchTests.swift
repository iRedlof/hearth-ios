import XCTest
@testable import HearthKit

final class CpFetchTests: XCTestCase {
    private let session = CpSession(token: "fixture", userId: 1, email: "person@example.com")
    private var location: CpLocation {
        CpLocation(name: "Amazon Day 1", address: "", deviceIds: [1], bounds: cpBounds(lat: 0, lon: 0))
    }

    private func client(_ status: String?, details: String? = nil) -> CpClient {
        CpClient(token: "fixture", userId: 1, transport: { request in
            let body = request.httpBody.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
            let text: String?
            if request.url!.absoluteString.contains("/sessions/") { text = details }
            else if body?["user_status"] != nil { text = status }
            else { text = nil }
            guard let text else { throw HaError("Fixture unavailable") }
            return (Data(text.utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        })
    }

    func testKnownChargingSessionSurvivesMissingDetails() async {
        let value = await fetchCpSnapshot(session, location: location,
            client: client(#"{"user_status":{"charging":{"sessionId":9,"state":"charging"}}}"#))
        XCTAssertEqual(value.unit, "kWh added")
        XCTAssertEqual(value.keys.map(\.command), ["open"])
        XCTAssertFalse(value.showOpen)
        XCTAssertFalse(value.autoOn)
    }

    func testStatusFailureRetainsChosenBuildingWithoutClaimingSetup() async {
        let value = await fetchCpSnapshot(session, location: location, client: client(nil))
        XCTAssertEqual(value.site, "Amazon Day 1")
        XCTAssertEqual(value.bigAnswer, "—")
        XCTAssertEqual(value.sub, "Couldn't check · Refresh to retry")
        XCTAssertEqual(value.checkedAt, "—")
    }

    func testFailedRefreshKeepsPreviousReadingsAndSuccessfulCheckTime() async {
        let old = CpSnapshot(site: "Amazon Day 1", account: "person", bigAnswer: "#3",
                             unit: "in line", sub: "43 chargers", plugsFree: nil,
                             autoOn: true, actionLabel: "Open", checkedAt: "8:30 AM")
        let value = await fetchCpSnapshot(session, location: location, client: client(nil), previous: old)
        XCTAssertEqual(value.bigAnswer, "#3")
        XCTAssertEqual(value.checkedAt, "8:30 AM")
        XCTAssertEqual(value.sub, "Couldn't check · Refresh to retry")
    }
}
