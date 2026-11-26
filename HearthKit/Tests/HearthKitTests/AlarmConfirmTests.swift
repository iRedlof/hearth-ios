import XCTest
@testable import HearthKit

final class AlarmConfirmTests: XCTestCase {
    // Android gates Disarm and Unlock behind biometric/dialog; Arm and Lock fire directly.
    func testDisarmNeedsConfirmationButArmDoesNot() {
        XCTAssertTrue(AlarmAction.disarm.needsConfirm)
        XCTAssertFalse(AlarmAction.armHome.needsConfirm)
        XCTAssertFalse(AlarmAction.armAway.needsConfirm)
    }

    func testUnlockNeedsConfirmationButLockDoesNot() {
        XCTAssertTrue(LockAction.unlock.needsConfirm)
        XCTAssertFalse(LockAction.lock.needsConfirm)
    }
}
