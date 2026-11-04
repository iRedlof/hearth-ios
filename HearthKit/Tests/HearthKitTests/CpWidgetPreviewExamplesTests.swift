import XCTest
@testable import HearthKit

final class CpWidgetPreviewExamplesTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    func testHeldWithoutSnoozesOffersOpenAndLeave() {
        let snapshot = cpWidgetPreviewSnapshot(.heldNoSnoozes, now: now)
        XCTAssertEqual(snapshot.keys.map(\.command), ["open", "leave"])
        XCTAssertEqual(snapshot.railNotes, ["Held for you", "No snoozes left"])
    }

    func testConfirmedAvailableSnoozeOffersOpenAndSnooze() {
        let snapshot = cpWidgetPreviewSnapshot(.heldSnoozeAvailable, now: now)
        XCTAssertEqual(snapshot.keys.map(\.command), ["open", "snooze"])
        XCTAssertEqual(snapshot.railNotes, ["Held for you", "1 snooze left"])
        XCTAssertEqual(snapshot.bigAnswer, "Held for you")
        XCTAssertEqual(snapshot.unit, "to plug in")
        XCTAssertTrue(snapshot.autoOn)
        XCTAssertEqual(snapshot.autoControl, .stop)
    }

    func testHeldCasesDifferOnlyInConfirmedAllowance() {
        var available = cpWidgetPreviewState(.heldSnoozeAvailable, now: now)
        let zero = cpWidgetPreviewState(.heldNoSnoozes, now: now)
        XCTAssertEqual(available.snoozesLeft, 1)
        XCTAssertEqual(zero.snoozesLeft, 0)
        available.snoozesLeft = 0
        XCTAssertEqual(available, zero)
    }

    func testInjectedReferenceTimeProducesSharedFutureHoldDeadline() {
        for example in [CpWidgetPreviewExample.heldSnoozeAvailable, .heldNoSnoozes] {
            let snapshot = cpWidgetPreviewSnapshot(example, now: now)
            XCTAssertEqual(snapshot.deadline, Date(timeIntervalSince1970: 1_700_001_800))
            XCTAssertEqual(snapshot.goTo, "EXAMPLE-29 P3")
            XCTAssertEqual(snapshot.account, "example")
            XCTAssertEqual(snapshot.site, "Workplace")
            XCTAssertEqual(snapshot, cpWidgetPreviewSnapshot(example, now: now))
        }
    }

    func testJoinExpiryRetainsIdentityWithoutSignedOutOrQueue() {
        let state = cpWidgetPreviewState(.sessionExpiredSignInRequired, now: now)
        XCTAssertFalse(state.signedOut)
        XCTAssertTrue(state.account.signedIn)
        XCTAssertTrue(state.account.needsReauth)
        XCTAssertTrue(state.autoOn)
        XCTAssertEqual(state.waitlist, .notQueued)
        XCTAssertNil(state.charging)
        XCTAssertNil(state.snoozesLeft)
        XCTAssertEqual(state.location?.title, "Workplace")

        let snapshot = cpWidgetPreviewSnapshot(.sessionExpiredSignInRequired, now: now)
        XCTAssertEqual(snapshot.account, "example")
        XCTAssertEqual(snapshot.site, "Workplace")
        XCTAssertEqual(snapshot.bigAnswer, "Sign in")
        XCTAssertEqual(snapshot.sub, "Use its own sign-in page")
        XCTAssertEqual(snapshot.actionLabel, "Sign in")
        XCTAssertFalse(snapshot.autoOn)
        XCTAssertEqual(snapshot.autoControl, .signin)
        XCTAssertTrue(snapshot.keys.isEmpty)
        XCTAssertNil(snapshot.deadline)
        XCTAssertNil(snapshot.goTo)
    }

    func testUnknownAllowanceDoesNotBecomeConfirmedZero() {
        var state = cpWidgetPreviewState(.heldNoSnoozes, now: now)
        state.snoozesLeft = nil
        let snapshot = cpSnapshot(state, email: "example", checkedAt: "", now: now)
        XCTAssertEqual(snapshot.keys.map(\.command), ["open", "leave"])
        XCTAssertEqual(snapshot.railNotes, ["Held for you"])
        XCTAssertNil(state.snoozesLeft)
    }

    func testMutatingReturnedStateCannotReplaceAnotherExample() {
        var changed = cpWidgetPreviewState(.heldSnoozeAvailable, now: now)
        changed.account = cpAccount(hasSession: false, expired: false)
        changed.signedOut = true
        changed.waitlist = .notQueued
        changed.snoozesLeft = 0
        changed.autoOn = false
        XCTAssertEqual(cpManualKeys(changed), [])

        let fresh = cpWidgetPreviewSnapshot(.heldSnoozeAvailable, now: now)
        XCTAssertEqual(fresh.keys.map(\.command), ["open", "snooze"])
        XCTAssertEqual(fresh.account, "example")
        XCTAssertEqual(fresh.deadline, Date(timeIntervalSince1970: 1_700_001_800))
        XCTAssertEqual(cpWidgetPreviewState(.heldNoSnoozes, now: now).snoozesLeft, 0)
    }

    func testExamplesHaveNoLiveCommandAuthorityOrRecoveryOverlay() {
        for example in CpWidgetPreviewExample.allCases {
            let snapshot = cpWidgetPreviewSnapshot(example, now: now)
            XCTAssertNil(snapshot.origin, example.rawValue)
            XCTAssertFalse(snapshot.stale, example.rawValue)
            XCTAssertFalse(snapshot.working, example.rawValue)
            XCTAssertNil(snapshot.statusDescription, example.rawValue)
            XCTAssertTrue(snapshot.stats.isEmpty, example.rawValue)
        }
    }

    func testGlobalOfferSampleAndDesignedFamiliesRemainAvailable() {
        XCTAssertEqual(CpSnapshot.sample.bigAnswer, "Your turn")
        XCTAssertEqual(CpSnapshot.sample.keys.map(\.command), ["accept", "snooze"])
        XCTAssertEqual(WidgetPreviewKind.chargepoint.supportedFamilies, [.medium])
        XCTAssertEqual(WidgetPreviewKind.allCases.count, 10)
    }
}
