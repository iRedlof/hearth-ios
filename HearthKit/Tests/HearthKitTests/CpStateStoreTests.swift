import Foundation
import XCTest
@testable import HearthKit

final class CpStateStoreTests: XCTestCase {
    private func store() throws -> CpStateStore { CpStateStore(directory: try CpStoreFixture.directory(self)) }

    func testIndependentHandleReadsOneCoherentImportedContext() throws {
        let directory = try CpStoreFixture.directory(self)
        let before = try CpStateStore(directory: directory).bootstrap(legacy: CpStoreFixture.legacy, now: CpStoreFixture.now)
        let other = try CpStateStore(directory: directory).snapshot(now: CpStoreFixture.now)
        XCTAssertEqual(other, before)
        XCTAssertEqual(other.session, CpStoreFixture.session)
        XCTAssertEqual(other.location, CpStoreFixture.location)
        XCTAssertEqual(other.run, CpStoreFixture.run)
        XCTAssertEqual(other.alerts, CpStoreFixture.alerts)
        XCTAssertEqual(other.udid, CpStoreFixture.udid)
        for generation in [other.context.accountGeneration, other.context.selectionRevision,
                           other.context.runID, other.context.modeRevision, other.context.settingsRevision] {
            XCTAssertNotNil(UUID(uuidString: generation))
        }
    }

    func testAccountReturningToSameUserDoesNotReviveOldSettingsOrReads() throws {
        let store = try store()
        let a = try store.bootstrap(legacy: CpStoreFixture.legacy, now: CpStoreFixture.now)
        let readA = try XCTUnwrap(store.beginRead(expected: a.context, now: CpStoreFixture.now))
        let out = try XCTUnwrap(store.edit(expected: a.settingsOrigin, edit: .signOut, now: CpStoreFixture.now))
        let signIn = try XCTUnwrap(store.beginSignIn(expected: out.settingsOrigin, now: CpStoreFixture.now))
        let returned = try XCTUnwrap(store.replaceSession(owner: signIn, candidate: CpStoreFixture.session,
                                                        now: CpStoreFixture.now))
        XCTAssertNotEqual(returned.context.accountGeneration, a.context.accountGeneration)
        XCTAssertNotEqual(returned.context.runID, a.context.runID)
        XCTAssertNil(try store.edit(expected: a.settingsOrigin, edit: .location(CpStoreFixture.location),
                                    now: CpStoreFixture.now))
        XCTAssertNil(try store.commitRead(owner: readA, provider: CpStoreFixture.reading(1),
                                         observedAt: CpStoreFixture.now, now: CpStoreFixture.now))
        XCTAssertEqual(try store.snapshot(now: CpStoreFixture.now), returned)
    }

    func testSameUserReauthenticationRetainsHistoryButRotatesAccountAndRunBinding() throws {
        let store = try store()
        let before = try store.bootstrap(legacy: CpStoreFixture.legacy, now: CpStoreFixture.now)
        let owner = try XCTUnwrap(store.beginSignIn(expected: before.settingsOrigin, now: CpStoreFixture.now))
        var renewed = CpStoreFixture.session
        renewed.token = "another-inert-fixture-cookie"
        renewed.renewedAt = 1_000_000
        let after = try XCTUnwrap(store.replaceSession(owner: owner, candidate: renewed, now: CpStoreFixture.now))
        XCTAssertEqual(after.session, renewed)
        XCTAssertEqual(after.location, before.location)
        XCTAssertEqual(after.run, before.run)
        XCTAssertEqual(after.alerts, before.alerts)
        XCTAssertEqual(after.udid, before.udid)
        XCTAssertNotEqual(after.context.accountGeneration, before.context.accountGeneration)
        XCTAssertNotEqual(after.context.runID, before.context.runID)
    }

    func testAccountABARotatesEvenWhenTheOriginalUserReturns() throws {
        let store = try store()
        let a = try store.bootstrap(legacy: CpStoreFixture.legacy, now: CpStoreFixture.now)
        let toB = try XCTUnwrap(store.beginSignIn(expected: a.settingsOrigin, now: CpStoreFixture.now))
        let b = try XCTUnwrap(store.replaceSession(owner: toB,
            candidate: CpSession(token: "inert-b", userId: 18, email: "b@example.invalid"), now: CpStoreFixture.now))
        let toA = try XCTUnwrap(store.beginSignIn(expected: b.settingsOrigin, now: CpStoreFixture.now))
        let returned = try XCTUnwrap(store.replaceSession(owner: toA, candidate: CpStoreFixture.session,
                                                        now: CpStoreFixture.now))
        XCTAssertNotEqual(returned.context.accountGeneration, a.context.accountGeneration)
        XCTAssertNil(try store.edit(expected: a.settingsOrigin, edit: .signOut, now: CpStoreFixture.now))
        XCTAssertEqual(try store.snapshot(now: CpStoreFixture.now).session, CpStoreFixture.session)
    }

    func testInvalidSignInCandidateDoesNotReplaceTheCurrentAccount() throws {
        let store = try store()
        let before = try store.bootstrap(legacy: CpStoreFixture.legacy, now: CpStoreFixture.now)
        let owner = try XCTUnwrap(store.beginSignIn(expected: before.settingsOrigin, now: CpStoreFixture.now))
        XCTAssertNil(try store.replaceSession(owner: owner, candidate: CpSession(), now: CpStoreFixture.now))
        let after = try store.snapshot(now: CpStoreFixture.now)
        XCTAssertEqual(after.session, before.session)
        XCTAssertEqual(after.context, before.context)
        XCTAssertEqual(after.run, before.run)
    }

    func testOnlyLatestSignInAttemptCanReplaceSession() throws {
        let store = try store()
        let before = try store.bootstrap(now: CpStoreFixture.now)
        let first = try XCTUnwrap(store.beginSignIn(expected: before.settingsOrigin, now: CpStoreFixture.now))
        let second = try XCTUnwrap(store.beginSignIn(expected: before.settingsOrigin, now: CpStoreFixture.now))
        XCTAssertNotEqual(first.attemptID, second.attemptID)
        XCTAssertNil(try store.replaceSession(owner: first, candidate: CpStoreFixture.session, now: CpStoreFixture.now))
        XCTAssertNotNil(try store.replaceSession(owner: second, candidate: CpStoreFixture.session, now: CpStoreFixture.now))
    }

    func testLocationReturningToSameIDsDoesNotReviveOldReadOrEdit() throws {
        let store = try store()
        let a = try store.bootstrap(legacy: CpStoreFixture.legacy, now: CpStoreFixture.now)
        let readA = try XCTUnwrap(store.beginRead(expected: a.context, now: CpStoreFixture.now))
        let b = try XCTUnwrap(store.edit(expected: a.settingsOrigin, edit: .location(CpStoreFixture.otherLocation),
                                        now: CpStoreFixture.now))
        let returned = try XCTUnwrap(store.edit(expected: b.settingsOrigin, edit: .location(CpStoreFixture.location),
                                               now: CpStoreFixture.now))
        XCTAssertNotEqual(returned.context.selectionRevision, a.context.selectionRevision)
        XCTAssertNotEqual(returned.context.runID, a.context.runID)
        XCTAssertFalse(returned.run.armed)
        XCTAssertTrue(returned.run.snoozeUsed)
        XCTAssertEqual(returned.run.startedAt, 7)
        XCTAssertNil(try store.failRead(owner: readA, message: "Old request", now: CpStoreFixture.now))
        XCTAssertNil(try store.edit(expected: a.settingsOrigin, edit: .locationName("Stale name"),
                                    now: CpStoreFixture.now))
        XCTAssertEqual(try store.snapshot(now: CpStoreFixture.now), returned)
    }

    func testCosmeticLocationRenamePreservesReadAndTargetIdentity() throws {
        let store = try store()
        let before = try store.bootstrap(legacy: CpStoreFixture.legacy, now: CpStoreFixture.now)
        let read = try XCTUnwrap(store.beginRead(expected: before.context, now: CpStoreFixture.now))
        let renamed = try XCTUnwrap(store.edit(expected: before.settingsOrigin, edit: .locationName("Work"),
                                              now: CpStoreFixture.now))
        XCTAssertEqual(renamed.location?.label, "Work")
        XCTAssertEqual(renamed.context.accountGeneration, before.context.accountGeneration)
        XCTAssertEqual(renamed.context.selectionRevision, before.context.selectionRevision)
        XCTAssertEqual(renamed.context.runID, before.context.runID)
        XCTAssertEqual(renamed.context.modeRevision, before.context.modeRevision)
        XCTAssertNotEqual(renamed.context.settingsRevision, before.context.settingsRevision)
        XCTAssertNotNil(try store.commitRead(owner: read, provider: CpStoreFixture.reading(3),
                                             observedAt: CpStoreFixture.now, now: CpStoreFixture.now))
        XCTAssertEqual(try store.snapshot(now: CpStoreFixture.now).location?.label, "Work")
    }

    func testPauseKeepsHistoryAndCanUseCurrentModeDespiteOtherSettingsEdit() throws {
        let store = try store()
        let before = try store.bootstrap(legacy: CpStoreFixture.legacy, now: CpStoreFixture.now)
        _ = try store.edit(expected: before.settingsOrigin, edit: .alert(.offer, true), now: CpStoreFixture.now)
        let paused = try XCTUnwrap(store.edit(expected: before.settingsOrigin, edit: .pause, now: CpStoreFixture.now))
        var expected = CpStoreFixture.run
        expected.armed = false
        XCTAssertEqual(paused.run, expected)
        XCTAssertEqual(paused.context.runID, before.context.runID)
        XCTAssertNotEqual(paused.context.modeRevision, before.context.modeRevision)
        XCTAssertTrue(paused.alerts.offer)
        XCTAssertNil(try store.edit(expected: before.settingsOrigin, edit: .pause, now: CpStoreFixture.now))
    }

    func testStaleSettingsEditDoesNotEraseAnAcceptedNewerEdit() throws {
        let store = try store()
        let before = try store.bootstrap(legacy: CpStoreFixture.legacy, now: CpStoreFixture.now)
        let newer = try XCTUnwrap(store.edit(expected: before.settingsOrigin, edit: .alert(.offer, true),
                                            now: CpStoreFixture.now))
        XCTAssertNil(try store.edit(expected: before.settingsOrigin, edit: .alert(.accepted, false),
                                    now: CpStoreFixture.now))
        XCTAssertTrue(try store.snapshot(now: CpStoreFixture.now).alerts.accepted)
        let fresh = try XCTUnwrap(store.edit(expected: newer.settingsOrigin, edit: .alert(.accepted, false),
                                            now: CpStoreFixture.now))
        XCTAssertTrue(fresh.alerts.offer)
        XCTAssertFalse(fresh.alerts.accepted)
    }

    func testDifferentAccountClearsLocationAndRunButRetainsAlertsAndDeviceID() throws {
        let store = try store()
        let before = try store.bootstrap(legacy: CpStoreFixture.legacy, now: CpStoreFixture.now)
        let signIn = try XCTUnwrap(store.beginSignIn(expected: before.settingsOrigin, now: CpStoreFixture.now))
        let b = CpSession(token: "inert-b", userId: 18, email: "other@example.invalid")
        let after = try XCTUnwrap(store.replaceSession(owner: signIn, candidate: b, now: CpStoreFixture.now))
        XCTAssertEqual(after.session, b)
        XCTAssertNil(after.location)
        XCTAssertEqual(after.run, CpRun())
        XCTAssertEqual(after.alerts, before.alerts)
        XCTAssertEqual(after.udid, before.udid)
    }

    func testLatestReadWinsAndAnOlderFailureCannotEraseTheSuccessfulClock() throws {
        let store = try store()
        let before = try store.bootstrap(legacy: CpStoreFixture.legacy, now: CpStoreFixture.now)
        let old = try XCTUnwrap(store.beginRead(expected: before.context, now: CpStoreFixture.now))
        let later = CpStoreFixture.now.addingTimeInterval(1)
        let latest = try XCTUnwrap(store.beginRead(expected: before.context, now: later))
        let finished = later.addingTimeInterval(1)
        let saved = try XCTUnwrap(store.commitRead(owner: latest, provider: CpStoreFixture.reading(2),
                                                  observedAt: finished, now: finished))
        XCTAssertNil(try store.commitRead(owner: old, provider: CpStoreFixture.reading(9),
                                         observedAt: finished, now: finished))
        XCTAssertNil(try store.failRead(owner: old, message: "Old error", now: finished))
        XCTAssertEqual(try store.snapshot(now: finished), saved)
        XCTAssertEqual(saved.reading?.provider, CpStoreFixture.reading(2))
        XCTAssertEqual(saved.reading?.observedAt, finished)
        XCTAssertNil(saved.failure)
        XCTAssertNil(saved.activeRead)
        XCTAssertNil(try store.commitRead(owner: latest, provider: CpStoreFixture.reading(7),
                                         observedAt: finished, now: finished))
        XCTAssertEqual(try store.snapshot(now: finished), saved)
    }

    func testFailedLatestReadRetainsOriginalSuccessfulReadingAndItsTime() throws {
        let store = try store()
        let before = try store.bootstrap(legacy: CpStoreFixture.legacy, now: CpStoreFixture.now)
        let first = try XCTUnwrap(store.beginRead(expected: before.context, now: CpStoreFixture.now))
        let successfulAt = CpStoreFixture.now.addingTimeInterval(1)
        _ = try store.commitRead(owner: first, provider: CpStoreFixture.reading(3),
                                 observedAt: successfulAt, now: successfulAt)
        let attemptedAt = successfulAt.addingTimeInterval(10)
        let second = try XCTUnwrap(store.beginRead(expected: before.context, now: attemptedAt))
        let failed = try XCTUnwrap(store.failRead(owner: second, message: "Fixture offline", now: attemptedAt))
        XCTAssertEqual(failed.reading?.provider, CpStoreFixture.reading(3))
        XCTAssertEqual(failed.reading?.observedAt, successfulAt)
        XCTAssertEqual(failed.failure?.message, "Fixture offline")
        XCTAssertEqual(failed.failure?.attemptedAt, attemptedAt)
        XCTAssertNil(failed.activeRead)
    }

    func testReadCannotCommitAtItsLeaseDeadlineOrAfterClockMovedBeforeItsStart() throws {
        let store = try store()
        let before = try store.bootstrap(legacy: CpStoreFixture.legacy, now: CpStoreFixture.now)
        let owner = try XCTUnwrap(store.beginRead(expected: before.context, now: CpStoreFixture.now))
        let deadline = CpStoreFixture.now.addingTimeInterval(60)
        XCTAssertNil(try store.commitRead(owner: owner, provider: CpStoreFixture.reading(4),
                                         observedAt: deadline, now: deadline))
        let next = try XCTUnwrap(store.beginRead(expected: before.context, now: deadline))
        XCTAssertNil(try store.failRead(owner: next, message: "Clock reversed",
                                       now: deadline.addingTimeInterval(-1)))
        XCTAssertNil(try store.snapshot(now: deadline).reading)
    }

    func testNonFiniteClockCannotMutateAuthoritativeState() throws {
        let directory = try CpStoreFixture.directory(self)
        let store = CpStateStore(directory: directory)
        let before = try store.bootstrap(legacy: CpStoreFixture.legacy, now: CpStoreFixture.now)
        let bytes = try Data(contentsOf: directory.appendingPathComponent("cp-state.json"))
        XCTAssertThrowsError(try store.beginRead(expected: before.context,
                                                 now: Date(timeIntervalSince1970: .nan)))
        XCTAssertThrowsError(try store.edit(expected: before.settingsOrigin, edit: .signOut,
                                            now: Date(timeIntervalSince1970: .infinity)))
        XCTAssertEqual(try Data(contentsOf: directory.appendingPathComponent("cp-state.json")), bytes)
    }

    func testReadBegunArmedProjectsPausedModeAfterPause() throws {
        let directory = try CpStoreFixture.directory(self)
        let store = CpStateStore(directory: directory)
        let before = try store.bootstrap(legacy: CpStoreFixture.legacy, now: CpStoreFixture.now)
        let owner = try XCTUnwrap(store.beginRead(expected: before.context, now: CpStoreFixture.now))
        let paused = try XCTUnwrap(store.edit(expected: before.settingsOrigin, edit: .pause, now: CpStoreFixture.now))
        XCTAssertEqual(paused.activeRead, owner)
        let provider = CpStoreFixture.reading(3)
        let saved = try XCTUnwrap(store.commitRead(owner: owner, provider: provider,
            observedAt: CpStoreFixture.now, now: CpStoreFixture.now))
        let reopened = try CpStateStore(directory: directory).snapshot(now: CpStoreFixture.now)
        XCTAssertEqual(saved, reopened)
        XCTAssertEqual(reopened.run, cpPauseRun(before.run))
        XCTAssertEqual(reopened.reading?.provider, provider)
        XCTAssertFalse(try reopened.viewState.autoOn)
        let display = try reopened.displaySnapshot(now: CpStoreFixture.now)
        XCTAssertFalse(display.autoOn)
        XCTAssertEqual(display.autoControl, .resume)
        XCTAssertEqual(display.bigAnswer, "#3")
        XCTAssertEqual(display.site, "Office")
        XCTAssertEqual(display.account, "person")
    }

    func testCachedProviderReadingProjectsPausedModeAfterPause() throws {
        let directory = try CpStoreFixture.directory(self)
        let store = CpStateStore(directory: directory)
        let before = try store.bootstrap(legacy: CpStoreFixture.legacy, now: CpStoreFixture.now)
        let owner = try XCTUnwrap(store.beginRead(expected: before.context, now: CpStoreFixture.now))
        let provider = CpStoreFixture.reading(3)
        let saved = try XCTUnwrap(store.commitRead(owner: owner, provider: provider,
            observedAt: CpStoreFixture.now, now: CpStoreFixture.now))
        _ = try XCTUnwrap(store.edit(expected: saved.settingsOrigin, edit: .pause, now: CpStoreFixture.now))
        let reopened = try CpStateStore(directory: directory).snapshot(now: CpStoreFixture.now)
        XCTAssertEqual(reopened.reading, saved.reading)
        XCTAssertEqual(reopened.run, cpPauseRun(saved.run))
        let display = try reopened.displaySnapshot(now: CpStoreFixture.now)
        XCTAssertFalse(display.autoOn)
        XCTAssertEqual(display.autoControl, .resume)
        XCTAssertEqual(display.checkedAt, cpClockString(CpStoreFixture.now))
    }

    func testReadBegunBeforeRenameUsesCurrentBuildingOnCommit() throws {
        let directory = try CpStoreFixture.directory(self)
        let store = CpStateStore(directory: directory)
        let before = try store.bootstrap(legacy: CpStoreFixture.legacy, now: CpStoreFixture.now)
        let owner = try XCTUnwrap(store.beginRead(expected: before.context, now: CpStoreFixture.now))
        _ = try XCTUnwrap(store.edit(expected: before.settingsOrigin, edit: .locationName("Work"),
            now: CpStoreFixture.now))
        let provider = CpStoreFixture.reading(3)
        _ = try XCTUnwrap(store.commitRead(owner: owner, provider: provider,
            observedAt: CpStoreFixture.now, now: CpStoreFixture.now))
        let reopened = try CpStateStore(directory: directory).snapshot(now: CpStoreFixture.now)
        XCTAssertEqual(reopened.context.selectionRevision, before.context.selectionRevision)
        XCTAssertEqual(reopened.context.runID, before.context.runID)
        XCTAssertEqual(reopened.reading?.provider, provider)
        XCTAssertEqual(reopened.reading?.observedAt, CpStoreFixture.now)
        XCTAssertEqual(try reopened.viewState.location?.title, "Work")
        let display = try reopened.displaySnapshot(now: CpStoreFixture.now)
        XCTAssertEqual(display.site, "Work")
        XCTAssertEqual(display.bigAnswer, "#3")
        XCTAssertEqual(display.checkedAt, cpClockString(CpStoreFixture.now))
    }

    func testCachedProviderReadingUsesCurrentBuildingAfterRename() throws {
        let directory = try CpStoreFixture.directory(self)
        let store = CpStateStore(directory: directory)
        let before = try store.bootstrap(legacy: CpStoreFixture.legacy, now: CpStoreFixture.now)
        let owner = try XCTUnwrap(store.beginRead(expected: before.context, now: CpStoreFixture.now))
        let saved = try XCTUnwrap(store.commitRead(owner: owner, provider: CpStoreFixture.reading(3),
            observedAt: CpStoreFixture.now, now: CpStoreFixture.now))
        _ = try XCTUnwrap(store.edit(expected: saved.settingsOrigin, edit: .locationName("Work"),
            now: CpStoreFixture.now))
        let reopened = try CpStateStore(directory: directory).snapshot(now: CpStoreFixture.now)
        XCTAssertEqual(reopened.reading, saved.reading)
        XCTAssertEqual(reopened.context.selectionRevision, saved.context.selectionRevision)
        XCTAssertEqual(reopened.run, saved.run)
        XCTAssertEqual(try reopened.displaySnapshot(now: CpStoreFixture.now).site, "Work")
    }

    func testConfiguredWithoutReadingStaysPendingButKeepsLocalPause() throws {
        let store = try store()
        let armed = try store.bootstrap(legacy: CpStoreFixture.legacy, now: CpStoreFixture.now)
        XCTAssertNil(armed.reading)
        let display = try armed.displaySnapshot(now: CpStoreFixture.now)
        XCTAssertEqual(display.bigAnswer, "—")
        XCTAssertEqual(display.sub, "Reading pending")
        XCTAssertEqual(display.actionLabel, "Open")
        XCTAssertTrue(display.keys.isEmpty)
        XCTAssertFalse(display.showOpen)
        XCTAssertEqual(display.checkedAt, "—")
        XCTAssertTrue(display.autoOn)
        XCTAssertEqual(display.autoControl, .stop)
        XCTAssertEqual(display.autoWaitingForSignIn, false)
        XCTAssertEqual(display.autoIndicatorARGB, 0xFF34C759)
        XCTAssertEqual(display.autoAccessibilityLabel, "Auto on. Stop Auto")
        let paused = try XCTUnwrap(store.edit(expected: armed.settingsOrigin, edit: .pause, now: CpStoreFixture.now))
        let pending = try paused.displaySnapshot(now: CpStoreFixture.now)
        XCTAssertFalse(pending.autoOn)
        XCTAssertEqual(pending.autoControl, .disabled)
        XCTAssertEqual(pending.actionLabel, "Open")
        XCTAssertTrue(pending.keys.isEmpty)
    }

    func testConfirmedNotQueuedReadingOffersJoinOnlyWhenPaused() throws {
        let store = try store()
        let before = try store.bootstrap(legacy: CpStoreFixture.legacy, now: CpStoreFixture.now)
        let paused = try XCTUnwrap(store.edit(expected: before.settingsOrigin, edit: .pause, now: CpStoreFixture.now))
        let owner = try XCTUnwrap(store.beginRead(expected: paused.context, now: CpStoreFixture.now))
        let provider = CpProviderReading(waitlist: .notQueued,
            availability: CpNow(free: 7, inUse: 11, offline: 2, stations: 5))
        let saved = try XCTUnwrap(store.commitRead(owner: owner, provider: provider,
            observedAt: CpStoreFixture.now, now: CpStoreFixture.now))
        let display = try saved.displaySnapshot(now: CpStoreFixture.now)
        XCTAssertEqual(display.bigAnswer, "7")
        XCTAssertEqual(display.actionLabel, "Join")
        XCTAssertEqual(display.autoControl, .join)
        XCTAssertFalse(display.autoOn)
        XCTAssertTrue(display.showOpen)
    }

    func testNoReadingKeepsSignInAndChooseLocationNavigation() throws {
        let store = try store()
        let out = try store.bootstrap(now: CpStoreFixture.now)
        let signedOut = try out.displaySnapshot(now: CpStoreFixture.now)
        XCTAssertEqual(signedOut.actionLabel, "Sign in")
        XCTAssertEqual(signedOut.bigAnswer, "Sign in")
        let owner = try XCTUnwrap(store.beginSignIn(expected: out.settingsOrigin, now: CpStoreFixture.now))
        let signedIn = try XCTUnwrap(store.replaceSession(owner: owner, candidate: CpStoreFixture.session,
            now: CpStoreFixture.now))
        let choose = try signedIn.displaySnapshot(now: CpStoreFixture.now)
        XCTAssertEqual(choose.actionLabel, "Choose location")
        XCTAssertEqual(choose.bigAnswer, "Set up")
        XCTAssertEqual(choose.autoControl, .disabled)
    }

    func testUnknownAndExhaustedSnoozeAllowanceNeverExposeSnooze() throws {
        for allowance in [Int?.none, .some(0), .some(1)] {
            let store = try store()
            let before = try store.bootstrap(legacy: CpStoreFixture.legacy, now: CpStoreFixture.now)
            let owner = try XCTUnwrap(store.beginRead(expected: before.context, now: CpStoreFixture.now))
            let provider = CpProviderReading(
                waitlist: .inLine(place: nil, state: "ACCEPT_PENDING", stations: 43,
                    offer: CpOffer(deviceId: 1, port: 2, charger: "Fixture P3", untilMs: 2_000_000,
                                   startMs: 1_000_000), auto: false),
                snoozesLeft: allowance)
            let saved = try XCTUnwrap(store.commitRead(owner: owner, provider: provider,
                observedAt: CpStoreFixture.now, now: CpStoreFixture.now))
            XCTAssertEqual(saved.reading?.provider.snoozesLeft, allowance)
            let display = try saved.displaySnapshot(now: CpStoreFixture.now)
            XCTAssertEqual(display.keys.contains(where: { $0.command == "snooze" }), allowance == 1)
            XCTAssertEqual(display.keys.contains(where: { $0.command == "leave" }), allowance != 1)
        }
    }

    func testRetainedFailureProjectsCurrentLocalModeAndOriginalSuccessfulTime() throws {
        let store = try store()
        let before = try store.bootstrap(legacy: CpStoreFixture.legacy, now: CpStoreFixture.now)
        let first = try XCTUnwrap(store.beginRead(expected: before.context, now: CpStoreFixture.now))
        let saved = try XCTUnwrap(store.commitRead(owner: first, provider: CpStoreFixture.reading(3),
            observedAt: CpStoreFixture.now, now: CpStoreFixture.now))
        let paused = try XCTUnwrap(store.edit(expected: saved.settingsOrigin, edit: .pause, now: CpStoreFixture.now))
        let later = CpStoreFixture.now.addingTimeInterval(10)
        let second = try XCTUnwrap(store.beginRead(expected: paused.context, now: later))
        let failed = try XCTUnwrap(store.failRead(owner: second, message: "Fixture offline", now: later))
        let display = try failed.displaySnapshot(now: later)
        XCTAssertEqual(display.checkedAt, cpClockString(CpStoreFixture.now))
        XCTAssertEqual(display.bigAnswer, "#3")
        XCTAssertTrue(display.stale)
        XCTAssertEqual(display.sub, "Couldn't check · Refresh to retry")
        XCTAssertFalse(display.autoOn)
        XCTAssertEqual(display.autoControl, .resume)
    }

    func testProviderReadingCodableRoundTripKeepsTypedEvidenceWithoutLocalPresentation() throws {
        let directory = try CpStoreFixture.directory(self)
        let store = CpStateStore(directory: directory)
        let before = try store.bootstrap(legacy: CpStoreFixture.legacy, now: CpStoreFixture.now)
        let offer = CpOffer(deviceId: 1, port: 2, charger: "Provider fixture P3",
                            untilMs: 2_000_000, startMs: 1_000_000)
        let cases = [
            CpProviderReading(),
            CpProviderReading(waitlist: .inLine(place: nil, state: "NEW_PROVIDER_STATE", stations: 0,
                                               offer: nil, auto: false)),
            CpStoreFixture.reading(3),
            CpProviderReading(waitlist: .inLine(place: nil, state: "ACCEPT_PENDING", stations: 43,
                                               offer: offer, auto: false), snoozesLeft: nil),
            CpProviderReading(waitlist: .inLine(place: nil, state: "PENDING_PLUG_IN", stations: 43,
                                               offer: offer, auto: false), snoozesLeft: 0),
            CpProviderReading(waitlist: .inLine(place: nil, state: "PASS", stations: 43,
                offer: CpOffer(deviceId: 0, port: 0, charger: "", untilMs: 2_000_000), auto: true)),
            CpProviderReading(charging: CpCharging(sessionId: 21, powerKw: nil, energyKwh: nil,
                minutes: nil, canStop: false)),
            CpProviderReading(charging: CpCharging(sessionId: 22, powerKw: 7.4, energyKwh: 3.2,
                minutes: 30, canStop: true, miles: 14, seconds: 1_800,
                vehicle: "Provider vehicle", charger: "Provider charger P3")),
            CpProviderReading(availability: CpNow(free: 7, inUse: 11, offline: 2, stations: 5),
                floors: [CpFloor(level: "P3", free: 7, total: 20)], snoozesLeft: 1)
        ]
        for provider in cases {
            let owner = try XCTUnwrap(store.beginRead(expected: before.context, now: CpStoreFixture.now))
            let saved = try XCTUnwrap(store.commitRead(owner: owner, provider: provider,
                observedAt: CpStoreFixture.now, now: CpStoreFixture.now))
            let reopened = try CpStateStore(directory: directory).snapshot(now: CpStoreFixture.now)
            XCTAssertEqual(reopened.reading, saved.reading)
            XCTAssertEqual(reopened.reading?.provider, provider)
            let root = try XCTUnwrap(JSONSerialization.jsonObject(
                with: Data(contentsOf: directory.appendingPathComponent("cp-state.json"))) as? [String: Any])
            XCTAssertEqual(root["version"] as? Int, 2)
            let reading = try XCTUnwrap(root["reading"] as? [String: Any])
            XCTAssertNil(reading["snapshot"])
            let evidence = try XCTUnwrap(reading["provider"] as? [String: Any])
            for forbidden in ["site", "account", "autoOn", "autoControl", "actionLabel", "keys", "railNotes",
                              "checkedAt", "working", "stale", "run"] {
                XCTAssertNil(evidence[forbidden], forbidden)
            }
        }
    }

    func testProviderReadingRejectsMalformedDiscriminatorAndNegativeKnownCounts() throws {
        let data = try JSONEncoder().encode(CpStoreFixture.reading(3))
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        var waitlist = try XCTUnwrap(object["waitlist"] as? [String: Any])
        waitlist["kind"] = "invented"
        object["waitlist"] = waitlist
        let malformed = try JSONSerialization.data(withJSONObject: object)
        XCTAssertThrowsError(try JSONDecoder().decode(CpProviderReading.self, from: malformed))
        for provider in [
            CpProviderReading(snoozesLeft: -1),
            CpProviderReading(availability: CpNow(free: Int.max, inUse: 1, offline: 0, stations: 1)),
            CpProviderReading(charging: CpCharging(sessionId: 1, powerKw: Double.nan,
                energyKwh: nil, minutes: nil, canStop: false)),
            CpProviderReading(charging: CpCharging(sessionId: 1, powerKw: nil,
                energyKwh: nil, minutes: Int.max, canStop: false)),
            CpProviderReading(charging: CpCharging(sessionId: 1, powerKw: nil,
                energyKwh: nil, minutes: nil, canStop: false, miles: Double(Int.max)))
        ] {
            XCTAssertThrowsError(try JSONEncoder().encode(provider))
        }
    }

    func testOversizedFailureDoesNotCommitOrConsumeReadOwner() throws {
        let directory = try CpStoreFixture.directory(self)
        let store = CpStateStore(directory: directory)
        let before = try store.bootstrap(legacy: CpStoreFixture.legacy, now: CpStoreFixture.now)
        let first = try XCTUnwrap(store.beginRead(expected: before.context, now: CpStoreFixture.now))
        let saved = try XCTUnwrap(store.commitRead(owner: first, provider: CpStoreFixture.reading(3),
            observedAt: CpStoreFixture.now, now: CpStoreFixture.now))
        let later = CpStoreFixture.now.addingTimeInterval(1)
        let second = try XCTUnwrap(store.beginRead(expected: saved.context, now: later))
        let path = directory.appendingPathComponent("cp-state.json")
        let bytes = try Data(contentsOf: path)
        var accepted: CpStoreSnapshot?
        XCTAssertThrowsError(accepted = try store.failRead(owner: second,
            message: String(repeating: "a", count: 256 * 1024 + 1), now: later)) {
            XCTAssertEqual($0 as? CpStateStoreError, .corrupt)
        }
        XCTAssertNil(accepted)
        XCTAssertEqual(try Data(contentsOf: path), bytes)
        let reopened = try CpStateStore(directory: directory).snapshot(now: later)
        XCTAssertEqual(reopened.activeRead, second)
        XCTAssertEqual(reopened.reading, saved.reading)
        XCTAssertNil(reopened.failure)
    }

    func testJoinExpiredWithoutReadingRetainsLocalAutoUntilPause() throws {
        let directory = try CpStoreFixture.directory(self)
        let store = CpStateStore(directory: directory)
        var session = CpStoreFixture.session
        session.joinExpired = true
        let legacy = CpLegacyState(session: session, location: CpStoreFixture.location,
            runWire: CpStoreFixture.runWire, alerts: CpStoreFixture.alerts, udid: CpStoreFixture.udid)
        _ = try store.bootstrap(legacy: legacy, now: CpStoreFixture.now)
        let armed = try CpStateStore(directory: directory).snapshot(now: CpStoreFixture.now)
        XCTAssertTrue(armed.run.armed)
        XCTAssertNil(armed.reading)
        let display = try armed.displaySnapshot(now: CpStoreFixture.now)
        XCTAssertEqual(display.bigAnswer, "Sign in")
        XCTAssertEqual(display.sub, "Session expired\nAuto waiting")
        XCTAssertEqual(display.actionLabel, "Sign in")
        XCTAssertEqual(display.account, "person")
        XCTAssertEqual(display.site, "Office")
        XCTAssertTrue(display.autoOn)
        XCTAssertEqual(display.autoControl, .stop)
        XCTAssertEqual(display.checkedAt, "—")
        XCTAssertEqual(display.autoWaitingForSignIn, true)
        XCTAssertEqual(display.autoIndicatorARGB, 0xFF626A63)
        XCTAssertEqual(display.autoAccessibilityLabel, "Auto enabled. Waiting for sign in. Pause Auto.")
        _ = try XCTUnwrap(store.edit(expected: armed.settingsOrigin, edit: .pause, now: CpStoreFixture.now))
        let paused = try CpStateStore(directory: directory).snapshot(now: CpStoreFixture.now)
        XCTAssertEqual(paused.run, cpPauseRun(CpStoreFixture.run))
        XCTAssertEqual(paused.session, session)
        let after = try paused.displaySnapshot(now: CpStoreFixture.now)
        XCTAssertFalse(after.autoOn)
        XCTAssertEqual(after.autoControl, .signin)
        XCTAssertEqual(after.actionLabel, "Sign in")
        XCTAssertEqual(after.autoWaitingForSignIn, false)
        XCTAssertEqual(after.autoAccessibilityLabel, "Auto off. Sign in to start Auto")
    }

    func testJoinExpiredCachedProviderReadingRetainsLocalAutoAndObservedTimeUntilPause() throws {
        let directory = try CpStoreFixture.directory(self)
        let store = CpStateStore(directory: directory)
        var session = CpStoreFixture.session
        session.joinExpired = true
        let legacy = CpLegacyState(session: session, location: CpStoreFixture.location,
            runWire: CpStoreFixture.runWire, alerts: CpStoreFixture.alerts, udid: CpStoreFixture.udid)
        let before = try store.bootstrap(legacy: legacy, now: CpStoreFixture.now)
        let owner = try XCTUnwrap(store.beginRead(expected: before.context, now: CpStoreFixture.now))
        let observedAt = CpStoreFixture.now.addingTimeInterval(1)
        let provider = CpStoreFixture.reading(3)
        _ = try XCTUnwrap(store.commitRead(owner: owner, provider: provider,
            observedAt: observedAt, now: observedAt))
        let armed = try CpStateStore(directory: directory).snapshot(now: observedAt)
        XCTAssertEqual(armed.reading?.provider, provider)
        XCTAssertEqual(armed.reading?.observedAt, observedAt)
        let display = try armed.displaySnapshot(now: observedAt.addingTimeInterval(10))
        XCTAssertEqual(display.bigAnswer, "Sign in")
        XCTAssertEqual(display.sub, "Session expired\nAuto waiting")
        XCTAssertEqual(display.actionLabel, "Sign in")
        XCTAssertEqual(display.checkedAt, cpClockString(observedAt))
        XCTAssertTrue(display.autoOn)
        XCTAssertEqual(display.autoControl, .stop)
        XCTAssertEqual(display.autoWaitingForSignIn, true)
        XCTAssertEqual(display.autoIndicatorARGB, 0xFF626A63)
        XCTAssertEqual(display.autoAccessibilityLabel, "Auto enabled. Waiting for sign in. Pause Auto.")
        _ = try XCTUnwrap(store.edit(expected: armed.settingsOrigin, edit: .pause, now: observedAt))
        let paused = try CpStateStore(directory: directory).snapshot(now: observedAt)
        XCTAssertEqual(paused.run, cpPauseRun(before.run))
        XCTAssertEqual(paused.reading, armed.reading)
        let after = try paused.displaySnapshot(now: observedAt.addingTimeInterval(10))
        XCTAssertFalse(after.autoOn)
        XCTAssertEqual(after.autoControl, .signin)
        XCTAssertEqual(after.checkedAt, cpClockString(observedAt))
        XCTAssertEqual(after.autoWaitingForSignIn, false)
    }

    func testChargingProviderReadingKeepsLocalAutoUntilPauseWithoutOfferingResume() throws {
        let directory = try CpStoreFixture.directory(self)
        let store = CpStateStore(directory: directory)
        let before = try store.bootstrap(legacy: CpStoreFixture.legacy, now: CpStoreFixture.now)
        let owner = try XCTUnwrap(store.beginRead(expected: before.context, now: CpStoreFixture.now))
        let observedAt = CpStoreFixture.now.addingTimeInterval(1)
        let provider = CpProviderReading(charging: CpCharging(sessionId: 22, powerKw: 7.4, energyKwh: 3.2,
            minutes: 30, canStop: true, miles: 14, seconds: 1_800,
            vehicle: "Provider vehicle", charger: "Provider charger P3"))
        _ = try XCTUnwrap(store.commitRead(owner: owner, provider: provider,
            observedAt: observedAt, now: observedAt))
        let armed = try CpStateStore(directory: directory).snapshot(now: observedAt)
        let display = try armed.displaySnapshot(now: observedAt.addingTimeInterval(10))
        XCTAssertEqual(display.bigAnswer, "3.2")
        XCTAssertEqual(display.unit, "kWh added")
        XCTAssertEqual(display.actionLabel, "Open")
        XCTAssertTrue(display.keys.contains(where: { $0.command == "stop" }))
        XCTAssertTrue(display.stats.contains(where: { $0.label == "Charger" }))
        XCTAssertEqual(display.checkedAt, cpClockString(observedAt))
        XCTAssertTrue(display.autoOn)
        XCTAssertEqual(display.autoControl, .stop)
        XCTAssertEqual(display.autoWaitingForSignIn, false)
        XCTAssertEqual(display.autoIndicatorARGB, 0xFF34C759)
        _ = try XCTUnwrap(store.edit(expected: armed.settingsOrigin, edit: .pause, now: observedAt))
        let paused = try CpStateStore(directory: directory).snapshot(now: observedAt)
        XCTAssertEqual(paused.run, cpPauseRun(before.run))
        XCTAssertEqual(paused.reading, armed.reading)
        let after = try paused.displaySnapshot(now: observedAt.addingTimeInterval(10))
        XCTAssertEqual(after.bigAnswer, "3.2")
        XCTAssertEqual(after.unit, "kWh added")
        XCTAssertFalse(after.autoOn)
        XCTAssertEqual(after.autoControl, .disabled)
        XCTAssertEqual(after.checkedAt, cpClockString(observedAt))
    }

    private func authenticationWaitingStore() throws -> CpStateStore {
        let value = try store()
        var session = CpStoreFixture.session
        session.joinExpired = true
        _ = try value.bootstrap(legacy: CpLegacyState(session: session, location: CpStoreFixture.location,
            runWire: CpStoreFixture.runWire, alerts: CpStoreFixture.alerts), now: CpStoreFixture.now)
        return value
    }

    func testAuthenticationWaitingPauseUsesLocalRuntimeAndRejectsStaleModeOrigin() async throws {
        let directory = try CpStoreFixture.directory(self)
        let value = CpStateStore(directory: directory)
        var session = CpStoreFixture.session
        session.joinExpired = true
        let before = try value.bootstrap(legacy: CpLegacyState(session: session,
            location: CpStoreFixture.location, runWire: CpStoreFixture.runWire), now: CpStoreFixture.now)
        let read = try XCTUnwrap(value.beginRead(expected: before.context, now: CpStoreFixture.now))
        let saved = try XCTUnwrap(value.commitRead(owner: read, provider: CpStoreFixture.reading(3),
            observedAt: CpStoreFixture.now, now: CpStoreFixture.now))
        let origin = try XCTUnwrap(saved.renderedOrigin)
        let instant = CpStoreFixture.now
        let runtime = CpOwnedRuntime(store: value, directory: directory, transport: CpPauseNoRequestTransport(),
            now: { instant })
        let result = try await runtime.setAuto(origin: origin, desired: .pause)
        XCTAssertNil(result.activatedMode)
        XCTAssertFalse(result.snapshot.autoOn)
        XCTAssertEqual(result.snapshot.autoWaitingForSignIn, false)
        let paused = try value.snapshot(now: instant)
        XCTAssertEqual(paused.run, cpPauseRun(saved.run))
        XCTAssertEqual(paused.session, saved.session)
        XCTAssertEqual(paused.location, saved.location)
        XCTAssertEqual(paused.reading, saved.reading)
        XCTAssertNil(paused.operation)
        XCTAssertEqual(try value.claimAuto(origin: origin, desired: .pause, now: instant), .rejected(.detailsChanged))
    }

    func testCurrent401WaitsWithSignedOutIdentityAndKeepsCachedDataAndIntent() throws {
        let value = try store()
        let before = try value.bootstrap(legacy: CpStoreFixture.legacy, now: CpStoreFixture.now)
        let first = try XCTUnwrap(value.beginRead(expected: before.context, now: CpStoreFixture.now))
        let saved = try XCTUnwrap(value.commitRead(owner: first, provider: CpStoreFixture.reading(3),
            observedAt: CpStoreFixture.now, now: CpStoreFixture.now))
        let read = try XCTUnwrap(value.beginRead(expected: saved.context, now: CpStoreFixture.now))
        let credential = try XCTUnwrap(value.requestCredential(authority: .read(read), purpose: .status, now: CpStoreFixture.now))
        let admission = try XCTUnwrap(value.authorizeAndStart(credential: credential, purpose: .status,
            now: CpStoreFixture.now) { _ in })
        XCTAssertTrue(try value.commitResponse(admission: admission, metadata: CpResponseMetadata(status: 401),
            now: CpStoreFixture.now))
        let expired = try value.snapshot(now: CpStoreFixture.now)
        let display = try expired.displaySnapshot(now: CpStoreFixture.now.addingTimeInterval(10))
        XCTAssertEqual(display.bigAnswer, "Sign in")
        XCTAssertEqual(display.account, "Signed out")
        XCTAssertEqual(display.site, "Office")
        XCTAssertEqual(display.sub, "Session expired\nAuto waiting")
        XCTAssertEqual(display.autoIndicatorARGB, 0xFF626A63)
        XCTAssertEqual(display.autoAccessibilityLabel, "Auto enabled. Waiting for sign in. Pause Auto.")
        XCTAssertEqual(display.autoControl, .stop)
        XCTAssertEqual(expired.run, saved.run)
        XCTAssertEqual(expired.reading, saved.reading)
        XCTAssertEqual(display.checkedAt, cpClockString(CpStoreFixture.now))
        XCTAssertEqual(expired.session.token, saved.session.token)
    }

    func testKnownSignInRequirementDoesNotInventAnExpiryCause() throws {
        let base = try store().bootstrap(legacy: CpStoreFixture.legacy, now: CpStoreFixture.now)
        // A display input contract, not a claim that explicit Sign out preserves armed state.
        var required = CpStoreSnapshot(session: CpSession(), location: base.location, run: base.run,
            alerts: base.alerts, udid: base.udid, context: base.context, reading: nil, failure: nil, activeRead: nil)
        required.renderedOrigin = base.renderedOrigin
        let display = try required.displaySnapshot(now: CpStoreFixture.now)
        XCTAssertEqual(display.bigAnswer, "Sign in")
        XCTAssertEqual(display.account, "Signed out")
        XCTAssertEqual(display.sub, "Sign in required\nAuto waiting")
        XCTAssertEqual(display.autoWaitingForSignIn, true)
        XCTAssertEqual(display.autoIndicatorARGB, 0xFF626A63)
    }

    func testExplicitSignOutDoesNotKeepAnArmedWaitingClaim() throws {
        let value = try authenticationWaitingStore()
        let before = try value.snapshot(now: CpStoreFixture.now)
        let signedOut = try XCTUnwrap(value.edit(expected: before.settingsOrigin, edit: .signOut, now: CpStoreFixture.now))
        let display = try signedOut.displaySnapshot(now: CpStoreFixture.now)
        XCTAssertFalse(signedOut.run.armed)
        XCTAssertNil(signedOut.location)
        XCTAssertNil(signedOut.reading)
        XCTAssertFalse(display.autoOn)
        XCTAssertEqual(display.autoWaitingForSignIn, false)
        XCTAssertEqual(display.autoControl, .disabled)
        XCTAssertEqual(display.autoAccessibilityLabel, "Auto off. Unavailable")
    }

    func testAuthenticationWaitingWithNoOriginAnnouncesStatusWithoutPause() throws {
        var owned = try authenticationWaitingStore().snapshot(now: CpStoreFixture.now)
        owned.renderedOrigin = nil
        let display = try owned.displaySnapshot(now: CpStoreFixture.now)
        XCTAssertNil(display.origin)
        XCTAssertEqual(display.autoControl, .stop)
        XCTAssertEqual(display.autoIndicatorARGB, 0xFF626A63)
        XCTAssertEqual(display.autoAccessibilityLabel, "Auto enabled. Waiting for sign in.")
    }

    func testElapsedCachedAssignmentCannotEraseAuthenticationSignIn() throws {
        let value = try authenticationWaitingStore()
        let before = try value.snapshot(now: CpStoreFixture.now)
        let read = try XCTUnwrap(value.beginRead(expected: before.context, now: CpStoreFixture.now))
        let observation = try cpOwnedObservation(statusJson:
            "{\"user_status\":{\"waitlist\":{\"state\":{\"state\":\"ACCEPT_PENDING\",\"token\":\"inert-offer\",\"deviceId\":1,\"portNo\":1,\"startTimeUTC\":999,\"duration\":1},\"stations\":[{\"deviceId\":1},{\"deviceId\":2}]}}}")
        let saved = try XCTUnwrap(value.commitObservation(owner: read, observation: observation,
            observedAt: CpStoreFixture.now, now: CpStoreFixture.now))
        XCTAssertNotNil(saved.providerActionable)
        let display = try saved.displaySnapshot(now: CpStoreFixture.now)
        XCTAssertEqual(display.bigAnswer, "Sign in")
        XCTAssertEqual(display.actionLabel, "Sign in")
        XCTAssertEqual(display.sub, "Session expired\nAuto waiting")
        XCTAssertNil(display.deadline)
        XCTAssertTrue(display.keys.isEmpty)
        XCTAssertEqual(try value.snapshot(now: CpStoreFixture.now).reading, saved.reading)
        XCTAssertEqual(try value.snapshot(now: CpStoreFixture.now).run, before.run)
    }

    func testAuthenticationWaitingPreservesReadFailureHelperAndObservedTime() throws {
        let value = try authenticationWaitingStore()
        let before = try value.snapshot(now: CpStoreFixture.now)
        let first = try XCTUnwrap(value.beginRead(expected: before.context, now: CpStoreFixture.now))
        _ = try value.commitRead(owner: first, provider: CpStoreFixture.reading(3),
            observedAt: CpStoreFixture.now, now: CpStoreFixture.now)
        let later = CpStoreFixture.now.addingTimeInterval(10)
        let read = try XCTUnwrap(value.beginRead(expected: before.context, now: later))
        let failed = try XCTUnwrap(value.failRead(owner: read, message: "Fixture offline", now: later))
        let display = try failed.displaySnapshot(now: later)
        XCTAssertEqual(display.sub, "Couldn't check · Refresh to retry")
        XCTAssertEqual(display.statusDescription, "Couldn't check. Refresh to retry.")
        XCTAssertEqual(display.autoIndicatorARGB, 0xFF626A63)
        XCTAssertEqual(display.autoAccessibilityLabel, "Auto enabled. Waiting for sign in. Pause Auto.")
        XCTAssertEqual(display.checkedAt, cpClockString(CpStoreFixture.now))
        XCTAssertTrue(display.stale)
    }

    func testAuthenticationWaitingDoesNotEraseOwnershipFeedback() throws {
        let base = try authenticationWaitingStore().snapshot(now: CpStoreFixture.now)
        for feedback in [CpFeedback.detailsChanged, .offerChanged, .sessionChanged, .noResponse] {
            var owned = base
            owned.ownershipFeedback = feedback
            let display = try owned.displaySnapshot(now: CpStoreFixture.now)
            XCTAssertEqual(display.sub, feedback.caption)
            XCTAssertEqual(display.statusDescription, feedback.message)
            XCTAssertEqual(display.autoIndicatorARGB, 0xFF626A63)
            XCTAssertEqual(display.autoAccessibilityLabel, "Auto enabled. Waiting for sign in. Pause Auto.")
        }
    }

    func testAuthenticationWaitingDoesNotEraseBusyOrUncertainOperation() throws {
        let base = try authenticationWaitingStore().snapshot(now: CpStoreFixture.now)
        let owner = CpOperationOwner(operationID: UUID().uuidString, claimRevision: UUID().uuidString,
            context: base.context, cause: .manual)
        let target = CpObservedIdentity(phase: "UNKNOWN", stationIDs: [], token: nil, deviceID: nil,
            port: nil, startMs: nil, deadlineMs: nil, sessionID: nil)
        for (stage, caption, spoken) in [
            (CpOperationStage.claimed, "Waiting\nto send", "Waiting to send join."),
            (.admitted, "Joining…", "Joining…"),
            (.uncertain, "No\nresponse", "No response · Refresh to check")
        ] {
            var owned = base
            owned.operation = CpOwnedOperation(owner: owner, action: .join, target: target,
                startedAt: CpStoreFixture.now, expiresAt: CpStoreFixture.now.addingTimeInterval(60),
                stage: stage)
            let display = try owned.displaySnapshot(now: CpStoreFixture.now)
            XCTAssertEqual(display.sub, caption)
            XCTAssertEqual(display.statusDescription, spoken)
            XCTAssertEqual(display.autoIndicatorARGB, 0xFF626A63)
            XCTAssertEqual(display.autoAccessibilityLabel, "Auto enabled. Waiting for sign in. Pause Auto.")
            XCTAssertEqual(display.autoControl, .stop)
            XCTAssertTrue(display.keys.isEmpty)
        }
    }

    func testMissingLocationAndUnknownProviderReadinessDoNotInventAuthenticationExpiry() throws {
        let value = try store()
        let base = try value.bootstrap(legacy: CpStoreFixture.legacy, now: CpStoreFixture.now)
        var unknown = base
        unknown.providerActionable = false
        let display = try unknown.displaySnapshot(now: CpStoreFixture.now)
        XCTAssertEqual(display.sub, "Reading pending")
        XCTAssertEqual(display.autoWaitingForSignIn, false)
        let missing = try XCTUnwrap(value.edit(expected: base.settingsOrigin, edit: .location(nil), now: CpStoreFixture.now))
        let setup = try missing.displaySnapshot(now: CpStoreFixture.now)
        XCTAssertEqual(setup.bigAnswer, "Set up")
        XCTAssertEqual(setup.autoWaitingForSignIn, false)
    }

    func testOlderSnapshotPayloadDecodesWithoutAuthenticationWaitingFact() throws {
        let display = try authenticationWaitingStore().snapshot(now: CpStoreFixture.now)
            .displaySnapshot(now: CpStoreFixture.now)
        let data = try JSONEncoder().encode(display)
        var payload = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        payload.removeValue(forKey: "autoWaitingForSignIn")
        let legacy = try JSONDecoder().decode(CpSnapshot.self, from: JSONSerialization.data(withJSONObject: payload))
        XCTAssertNil(legacy.autoWaitingForSignIn)
        XCTAssertEqual(legacy.autoIndicatorARGB, 0xFF34C759)
        XCTAssertEqual(legacy.autoAccessibilityLabel, "Auto on. Stop Auto")
        XCTAssertEqual(legacy.origin, display.origin)
        XCTAssertEqual(legacy.checkedAt, display.checkedAt)
        XCTAssertEqual(try JSONDecoder().decode(CpSnapshot.self, from: data), display)
    }

    func testPureGalleryExamplesKeepExistingIntentAndAuthenticationPresentation() {
        let held = cpWidgetPreviewSnapshot(.heldSnoozeAvailable, now: CpStoreFixture.now)
        XCTAssertNil(held.autoWaitingForSignIn)
        XCTAssertEqual(held.autoIndicatorARGB, 0xFF34C759)
        XCTAssertNil(held.origin)
        let expired = cpWidgetPreviewSnapshot(.sessionExpiredSignInRequired, now: CpStoreFixture.now)
        XCTAssertNil(expired.autoWaitingForSignIn)
        XCTAssertFalse(expired.autoOn)
        XCTAssertEqual(expired.sub, "Use its own sign-in page")
        XCTAssertEqual(expired.autoAccessibilityLabel, "Auto off. Sign in to start Auto")
        XCTAssertNil(CpSnapshot.sample.autoWaitingForSignIn)
        XCTAssertEqual(CpSnapshot.sample.bigAnswer, "Your turn")
    }
}

/// A local Pause must return before any transport is prepared, including status reads.
private struct CpPauseNoRequestTransport: CpOwnedTransport {
    func prepare(_ request: URLRequest) throws -> any CpPreparedRequest {
        XCTFail("Local authentication-waiting Pause must not prepare a provider request")
        throw CpFeedback.unavailable
    }
}
