import XCTest
@testable import HearthKit

final class CpKeysTests: XCTestCase {
    private func state(_ wl: CpWaitlist, charging: CpCharging? = nil, signedOut: Bool = false) -> CpState {
        CpState(signedOut: signedOut, account: cpAccount(hasSession: !signedOut, expired: false),
                location: nil, now: nil, waitlist: wl, charging: charging, autoOn: false)
    }

    func testKeysPerState() {
        func keys(_ s: String, _ auto: Bool = false) -> [String] {
            cpManualKeys(state(.inLine(place: nil, state: s, stations: 0, offer: nil, auto: auto))).map(\.command)
        }
        XCTAssertEqual(keys("ACCEPT_PENDING"), ["accept", "leave"])
        XCTAssertEqual(keys("PENDING_PLUG_IN"), ["open", "leave"])
        XCTAssertEqual(keys("DIB_PENDING_PLUG_IN"), ["open", "leave"])
        XCTAssertEqual(keys("PASS", true), ["unsnooze", "leave"])
        XCTAssertEqual(keys("WAITING"), ["leave"])
        XCTAssertEqual(keys("CHARGING_FAULT"), ["still", "done"])
        XCTAssertEqual(keys("DIB_PLUG_OUT"), ["still", "done"])
        XCTAssertTrue(cpManualKeys(state(.notQueued)).isEmpty)                 // idle → no manual keys
        XCTAssertTrue(cpManualKeys(state(.notQueued, signedOut: true)).isEmpty) // signed out → none
        let charging = CpCharging(sessionId: 1, powerKw: nil, energyKwh: nil, minutes: nil, canStop: true,
                                  miles: nil, seconds: nil, vehicle: nil, charger: nil)
        XCTAssertEqual(cpManualKeys(state(.notQueued, charging: charging)).map(\.command), ["stop"])
        let unsupported = CpCharging(sessionId: 1, powerKw: nil, energyKwh: nil, minutes: nil, canStop: false)
        XCTAssertEqual(cpManualKeys(state(.notQueued, charging: unsupported)).map(\.command), ["open"])
        XCTAssertEqual(keys("CHARGING"), ["open"])
        XCTAssertEqual(keys("PENDING_PLUG_OUT"), ["open"])
        XCTAssertEqual(keys("OVER_STAYED"), ["open"])
    }

    func testDeadlineFromOffer() {
        let until: Int64 = 1_700_000_900_000
        let offer = CpOffer(deviceId: 1, port: 1, charger: "C", untilMs: until)
        let s = state(.inLine(place: nil, state: "ACCEPT_PENDING", stations: 0, offer: offer, auto: false))
        XCTAssertEqual(cpDeadline(s), Date(timeIntervalSince1970: Double(until) / 1000))
        XCTAssertNil(cpDeadline(state(.inLine(place: nil, state: "WAITING", stations: 0, offer: offer, auto: false))))
        XCTAssertNil(cpDeadline(state(.notQueued)))
    }
}
