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
        XCTAssertEqual(keys("ACCEPT_PENDING"), ["accept", "snooze"])
        XCTAssertEqual(keys("PENDING_PLUG_IN"), ["start", "snooze"])
        XCTAssertEqual(keys("DIB_PENDING_PLUG_IN"), ["start", "snooze"])
        XCTAssertEqual(keys("PASS", true), ["unsnooze"])
        XCTAssertEqual(keys("WAITING"), ["leave"])
        XCTAssertEqual(keys("CHARGING_FAULT"), ["still", "done"])
        XCTAssertEqual(keys("DIB_PLUG_OUT"), ["still", "done"])
        XCTAssertTrue(cpManualKeys(state(.notQueued)).isEmpty)                 // idle → no manual keys
        XCTAssertTrue(cpManualKeys(state(.notQueued, signedOut: true)).isEmpty) // signed out → none
        let charging = CpCharging(sessionId: 1, powerKw: nil, energyKwh: nil, minutes: nil, canStop: true,
                                  miles: nil, seconds: nil, vehicle: nil, charger: nil)
        XCTAssertEqual(cpManualKeys(state(.notQueued, charging: charging)).map(\.command), ["stop"])
    }
}
