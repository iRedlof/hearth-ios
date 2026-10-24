import XCTest
@testable import HearthKit

final class DoorsTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_700_000_000)

    func testGarageActionsAndStatus() {
        let closed = doorView(Door(id: "cover.garage", name: "Garage", kind: .garage, state: "closed", since: nil), now: now)
        XCTAssertEqual(closed.action, .open)
        XCTAssertEqual(closed.open, false)
        let open = doorView(Door(id: "cover.garage", name: "Garage", kind: .garage, state: "open",
                                 since: now.addingTimeInterval(-180)), now: now)
        XCTAssertEqual(open.action, .close)
        XCTAssertEqual(open.open, true)
        XCTAssertTrue(open.status.hasPrefix("Open · 3 min"))
    }

    func testLockAndSensor() {
        let locked = doorView(Door(id: "lock.front", name: "Front Door", kind: .lock, state: "locked", since: nil), now: now)
        XCTAssertNil(locked.action); XCTAssertEqual(locked.open, false)
        let unlocked = doorView(Door(id: "lock.front", name: "Front Door", kind: .lock, state: "unlocked", since: nil), now: now)
        XCTAssertEqual(unlocked.action, .lock); XCTAssertEqual(unlocked.open, true)
        let sensor = doorView(Door(id: "binary_sensor.back", name: "Back", kind: .sensor, state: "on", since: nil), now: now)
        XCTAssertNil(sensor.action); XCTAssertEqual(sensor.open, true)   // sensors read-only
    }

    func testNeedsConfirmOnlyGarageOpen() {
        XCTAssertTrue(DoorAction.open.needsConfirm)
        XCTAssertFalse(DoorAction.close.needsConfirm)
        XCTAssertFalse(DoorAction.lock.needsConfirm)
    }

    func testHowLong() {
        XCTAssertEqual(howLong(30), "just now")
        XCTAssertEqual(howLong(5 * 60), "5 min")
        XCTAssertEqual(howLong(125 * 60), "2 h 5 min")
        XCTAssertEqual(howLong(120 * 60), "2 h")   // " 0 min" stripped
    }

    func testSummaryHeadlineTone() {
        let allShut = doorsSummary([Door(id: "cover.g", name: "Garage", kind: .garage, state: "closed", since: nil),
                                    Door(id: "lock.f", name: "Front Door", kind: .lock, state: "locked", since: nil)], now: now)
        XCTAssertEqual(allShut.headline, "All shut")
        XCTAssertEqual(allShut.tone, .calm)
        XCTAssertEqual(allShut.lockLine, "Front Door locked")
        let openOld = doorsSummary([Door(id: "cover.g", name: "Garage", kind: .garage, state: "open",
                                         since: now.addingTimeInterval(-40 * 60))], now: now)
        XCTAssertEqual(openOld.tone, .alert)   // open >= 30 min → forgotten
        XCTAssertEqual(openOld.headline, "Garage open")
    }
}
