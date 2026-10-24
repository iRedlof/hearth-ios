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
        XCTAssertEqual(keys("PENDING_PLUG_IN"), ["snooze"])
        XCTAssertEqual(keys("DIB_PENDING_PLUG_IN"), ["snooze"])
        XCTAssertEqual(keys("PASS", true), ["unsnooze"])
        XCTAssertEqual(keys("WAITING"), ["leave"])
        XCTAssertTrue(cpManualKeys(state(.notQueued)).isEmpty)                 // idle → no manual keys
        XCTAssertTrue(cpManualKeys(state(.notQueued, signedOut: true)).isEmpty) // signed out → none
    }
}
