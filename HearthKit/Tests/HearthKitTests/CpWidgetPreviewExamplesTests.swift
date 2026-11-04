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
        for example in [CpWidgetPreviewExample.heldSnoozeAvailable, .heldNoSnoozes, .sessionExpiredSignInRequired] {
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
    func testQueuedAutoExampleShowsPositionRatherThanHeldAssignment() {
        let example = CpWidgetPreviewExample.auto_waiting
        let state = cpWidgetPreviewState(example, now: now)
        let snapshot = cpWidgetPreviewSnapshot(example, now: now)
        XCTAssertEqual(snapshot.bigAnswer, "#3")
        XCTAssertEqual(snapshot.unit, "in line")
        XCTAssertEqual(snapshot.keys.map(\.command), ["leave"])
        XCTAssertTrue(state.autoOn)
        XCTAssertTrue(snapshot.autoOn)
        XCTAssertNil(snapshot.deadline)
        XCTAssertNil(snapshot.goTo)
    }

    func testAdditionalExamplesUseCanonicalAnswersAndManualKeys() {
        // Swapping a phase or charging authority in the consumed factory must fail here.
        let cases: [(CpWidgetPreviewExample, String, [String])] = [
            (.available, "78", []), (.signed_out, "Sign in", []), (.no_location, "Set up", []),
            (.waiting, "#3", ["leave"]), (.auto_waiting, "#3", ["leave"]),
            (.pending, cpClockString(now.addingTimeInterval(600)), ["leave"]),
            (.offer, "Your turn", ["accept", "snooze"]), (.offer_last, "Your turn", ["accept", "leave"]),
            (.held, "Held for you", ["open", "snooze"]), (.held_unknown, "Held for you", ["open", "leave"]),
            (.dib_held, "Held again", ["open", "snooze"]), (.offer_no_floor, "Your turn", ["accept", "snooze"]),
            (.unknown_deadline, "Your turn", ["accept", "snooze"]),
            (.snoozed, "Snoozed", ["unsnooze", "leave"]), (.auto_snoozed, "Snoozed", ["unsnooze", "leave"]),
            (.charging, "7.4", ["stop"]), (.charging_no_stop, "7.4", ["open"]),
            (.done, "Done charging", ["open"]), (.fault, "Not charging", ["still", "done"]),
            (.unplugged, "Unplugged", ["still", "done"]), (.overstayed, "Move your car", ["open"]),
            (.blocked, "Blocked", ["leave"])
        ]
        for (example, answer, commands) in cases {
            let snapshot = cpWidgetPreviewSnapshot(example, now: now)
            XCTAssertEqual(snapshot.bigAnswer, answer, example.id)
            XCTAssertEqual(snapshot.keys.map(\.command), commands, example.id)
            XCTAssertNil(snapshot.origin, example.id)
            XCTAssertNil(snapshot.autoWaitingForSignIn, example.id)
            XCTAssertFalse(snapshot.working, example.id)
        }
    }

    func testOfferAllowanceAndDeadlineUnknownRemainIndependent() {
        let available = cpWidgetPreviewSnapshot(.offer, now: now)
        let zero = cpWidgetPreviewSnapshot(.offer_last, now: now)
        let unknown = cpWidgetPreviewSnapshot(.held_unknown, now: now)
        XCTAssertEqual(available.railNotes, ["Your turn", "1 snooze left"])
        XCTAssertEqual(zero.railNotes, ["Your turn", "No snoozes left"])
        XCTAssertEqual(unknown.railNotes, ["Held for you"])
        XCTAssertNil(cpWidgetPreviewState(.held_unknown, now: now).snoozesLeft)
        XCTAssertEqual(cpWidgetPreviewState(.offer_last, now: now).snoozesLeft, 0)
        XCTAssertEqual(available.deadline, now.addingTimeInterval(1690))
        let deadlineUnknown = cpWidgetPreviewSnapshot(.unknown_deadline, now: now)
        XCTAssertNil(deadlineUnknown.deadline)
        XCTAssertEqual(deadlineUnknown.sub, "Deadline unknown")
        XCTAssertTrue(deadlineUnknown.autoOn)
        XCTAssertEqual(deadlineUnknown.keys.map(\.command), ["accept", "snooze"])
        guard case let .inLine(_, _, _, offer?, _) = cpWidgetPreviewState(.offer, now: now).waitlist else {
            return XCTFail("Offer must carry an assignment")
        }
        XCTAssertLessThan(offer.startMs, offer.untilMs)
        XCTAssertEqual(cpWidgetPreviewSnapshot(.offer_no_floor, now: now).goTo, "SEA41-29")
    }

    func testLocalAutoIntentDoesNotInventProviderMissedOfferOrLiveReadiness() {
        let pairs: [(CpWidgetPreviewExample, CpWidgetPreviewExample)] = [(.waiting, .auto_waiting), (.snoozed, .auto_snoozed)]
        for (off, on) in pairs {
            var offState = cpWidgetPreviewState(off, now: now)
            let onState = cpWidgetPreviewState(on, now: now)
            offState.autoOn = true
            XCTAssertEqual(offState, onState)
            XCTAssertFalse(cpWidgetPreviewSnapshot(off, now: now).autoOn)
            XCTAssertTrue(cpWidgetPreviewSnapshot(on, now: now).autoOn)
            XCTAssertEqual(cpWidgetPreviewSnapshot(on, now: now).autoControl, .stop)
            if case let .inLine(_, phase, _, _, providerAuto) = onState.waitlist {
                XCTAssertFalse(providerAuto)
                if phase == "PASS" { XCTAssertEqual(cpAnswer(onState).sub, "Place kept") }
            } else { XCTFail("Expected retained queue") }
        }
        XCTAssertFalse(cpWidgetPreviewSnapshot(.held, now: now).autoOn)
        XCTAssertEqual(cpWidgetPreviewSnapshot(.held, now: now).autoControl, .resume)
    }

    func testAvailabilityAuthenticationAndChargingAreNotInterchangeable() {
        let available = cpWidgetPreviewSnapshot(.available, now: now)
        XCTAssertEqual(available.plugsFree, "78 of 86 free")
        XCTAssertEqual(available.floors.map(\.free), [8, 17, 22, 21, 10])
        XCTAssertTrue(available.showOpen)
        let signedOut = cpWidgetPreviewSnapshot(.signed_out, now: now)
        XCTAssertEqual(signedOut.account, "Signed out")
        XCTAssertNil(signedOut.plugsFree)
        XCTAssertNil(signedOut.deadline)
        XCTAssertFalse(signedOut.autoOn)
        let noLocation = cpWidgetPreviewSnapshot(.no_location, now: now)
        XCTAssertEqual(noLocation.account, "example")
        XCTAssertEqual(noLocation.actionLabel, "Choose location")
        XCTAssertNil(noLocation.plugsFree)
        let charging = cpWidgetPreviewSnapshot(.charging, now: now)
        XCTAssertEqual(charging.unit, "kWh added")
        XCTAssertEqual(charging.sub, "6.6 kW now")
        XCTAssertFalse(charging.stats.isEmpty)
        XCTAssertFalse(charging.autoOn)
        XCTAssertEqual(charging.autoControl, .disabled)
        XCTAssertNil(charging.plugsFree)
        XCTAssertNil(charging.deadline)
    }

    func testAdditionalSamplesAreValueIndependentAndInjectedTimeControlsAssignment() {
        var edited = cpWidgetPreviewState(.offer_last, now: now)
        edited.signedOut = true
        edited.waitlist = .notQueued
        edited.autoOn = false
        XCTAssertTrue(cpManualKeys(edited).isEmpty)
        let fresh = cpWidgetPreviewSnapshot(.offer_last, now: now)
        XCTAssertEqual(fresh.keys.map(\.command), ["accept", "leave"])
        XCTAssertEqual(fresh.deadline, now.addingTimeInterval(1690))
        let later = cpWidgetPreviewSnapshot(.offer_last, now: now.addingTimeInterval(60))
        XCTAssertEqual(later.deadline, now.addingTimeInterval(1750))
        XCTAssertEqual(fresh.account, "example")
    }

}
