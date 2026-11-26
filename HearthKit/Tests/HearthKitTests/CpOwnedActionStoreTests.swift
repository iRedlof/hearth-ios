import Foundation
import XCTest
@testable import HearthKit

final class CpOwnedActionStoreTests: XCTestCase {
    private let now = CpStoreFixture.now

    private func store(armed: Bool = true) throws -> CpStateStore {
        let value = CpStateStore(directory: try CpStoreFixture.directory(self))
        _ = try value.bootstrap(legacy: CpLegacyState(session: CpStoreFixture.session,
            location: CpStoreFixture.location, runWire: armed ? "1|0|0|7|0|||": "0|0|0|7|0|||"),
            now: now)
        return value
    }

    private func observation(_ phase: String = "ACCEPT_PENDING", token: String = "private-offer",
                             ids: [Int64] = [1, 2], allowance: Int? = nil) throws -> CpObservation {
        var state: [String: Any] = ["state": phase]
        if !["NOT_QUEUED", "WAITING", "UNKNOWN"].contains(phase) {
            state.merge(["token": token, "deviceId": 1, "portNo": 2,
                "startTimeUTC": 999, "duration": 301]) { _, new in new }
        }
        let raw = String(decoding: try JSONSerialization.data(withJSONObject:
            ["user_status": ["waitlist": ["state": state, "stations": ids.map { ["deviceId": $0] }]]]), as: UTF8.self)
        return try cpOwnedObservation(statusJson: raw,
            details: CpDetailEvidence(allowanceToken: allowance == nil ? nil : token,
                allowanceJson: allowance.map { "{\"response\":{\"remainingSnoozeCount\":\($0)}}" }))
    }

    private func observed(_ store: CpStateStore, _ value: CpObservation,
                          at time: Date? = nil) throws -> CpStoreSnapshot {
        let time = time ?? now
        let owner = try XCTUnwrap(store.beginRead(expected: store.snapshot(now: time).context, now: time))
        return try XCTUnwrap(store.commitObservation(owner: owner, observation: value, observedAt: time, now: time))
    }

    private func owner(_ result: CpClaimResult, file: StaticString = #filePath, line: UInt = #line) throws -> CpOperationOwner {
        guard case let .claimed(value) = result else {
            XCTFail("Expected a claimed operation, got \(result)", file: file, line: line)
            throw CpFeedback.detailsChanged
        }
        return value
    }

    private func admitted(_ store: CpStateStore, _ owner: CpOperationOwner,
                          _ action: CpOwnedAction, at time: Date? = nil) throws -> CpDispatchAdmission {
        let time = time ?? now
        let credential = try XCTUnwrap(store.requestCredential(authority: .operation(owner),
            purpose: .mutation(action), now: time))
        return try XCTUnwrap(store.authorizeAndStart(credential: credential, purpose: .mutation(action), now: time) { _ in })
    }

    func testRenderedOriginContainsOnlyOpaqueLocalGenerations() throws {
        let value = try store()
        let snapshot = try observed(value, observation())
        let origin = try XCTUnwrap(snapshot.renderedOrigin)
        let encoded = try XCTUnwrap(origin.encoded())
        XCTAssertEqual(CpRenderedOrigin.decode(encoded), origin)
        XCTAssertFalse(encoded.contains(CpStoreFixture.session.token))
        XCTAssertFalse(encoded.contains("private-offer"))
        XCTAssertFalse(encoded.contains(CpStoreFixture.session.email))
    }

    func testUnobservedConfiguredContextCannotJoinOrResume() throws {
        let value = try store(armed: false)
        let snapshot = try value.snapshot(now: now)
        let origin = try XCTUnwrap(snapshot.renderedOrigin)
        XCTAssertEqual(try value.claim(origin: origin, action: .join, now: now), .rejected(.detailsChanged))
        XCTAssertEqual(try value.claimAuto(origin: origin, desired: .resume, now: now), .rejected(.detailsChanged))
    }

    func testDuplicateRenderedActionStaysConsumedAfterSuccessAndIdenticalRead() throws {
        let value = try store()
        let evidence = try observation()
        let old = try XCTUnwrap(observed(value, evidence).renderedOrigin)
        let operation = try owner(value.claim(origin: old, action: .accept, now: now))
        XCTAssertEqual(try value.claim(origin: old, action: .accept, now: now), .rejected(.detailsChanged))
        XCTAssertTrue(try value.validatePreflight(owner: operation, observation: evidence, now: now))
        _ = try admitted(value, operation, .accept)
        _ = try value.commitOutcome(owner: operation, outcome: .success, now: now)
        _ = try observed(value, evidence, at: now.addingTimeInterval(1))
        XCTAssertEqual(try value.claim(origin: old, action: .accept, now: now.addingTimeInterval(1)), .rejected(.detailsChanged))
    }

    func testIndependentStoresHaveExactlyOneClaimWinner() throws {
        let directory = try CpStoreFixture.directory(self)
        let initial = CpStateStore(directory: directory)
        _ = try initial.bootstrap(legacy: CpStoreFixture.legacy, now: now)
        let origin = try XCTUnwrap(observed(initial, observation()).renderedOrigin)
        let winners = CpClaimCounter()
        let instant = now
        DispatchQueue.concurrentPerform(iterations: 32) { _ in
            if case .claimed = try? CpStateStore(directory: directory).claim(origin: origin, action: .accept, now: instant) {
                winners.increment()
            }
        }
        XCTAssertEqual(winners.value, 1)
    }

    func testManualPreflightAndSuccessRetainPauseAndSpendSnooze() throws {
        let value = try store()
        let evidence = try observation("PENDING_PLUG_IN", allowance: 1)
        let initial = try observed(value, evidence)
        let operation = try owner(value.claim(origin: XCTUnwrap(initial.renderedOrigin), action: .snooze, now: now))
        _ = try XCTUnwrap(value.edit(expected: initial.settingsOrigin, edit: .pause, now: now))
        XCTAssertTrue(try value.validatePreflight(owner: operation, observation: evidence, now: now))
        _ = try admitted(value, operation, .snooze)
        let completed = try XCTUnwrap(value.commitOutcome(owner: operation, outcome: .success, now: now))
        XCTAssertFalse(completed.run.armed)
        XCTAssertTrue(completed.run.snoozeUsed)
        XCTAssertEqual(completed.context.runID, initial.context.runID)
    }

    func testSuccessfulSnoozeShowsSpentCaptionOnRetainedOfferAndHeldReadingBeforeAndAfterPause() throws {
        for phase in ["ACCEPT_PENDING", "PENDING_PLUG_IN"] {
            let value = try store()
            let evidence = try observation(phase, allowance: 1)
            let initial = try observed(value, evidence)
            let before = try initial.displaySnapshot(now: now)
            XCTAssertTrue(before.railNotes.contains("1 snooze left"))
            let operation = try owner(value.claim(origin: XCTUnwrap(initial.renderedOrigin), action: .snooze, now: now))
            XCTAssertTrue(try value.validatePreflight(owner: operation, observation: evidence, now: now))
            _ = try admitted(value, operation, .snooze)
            let completed = try XCTUnwrap(value.commitOutcome(owner: operation, outcome: .success, now: now))
            let paused = try XCTUnwrap(value.edit(expected: completed.settingsOrigin, edit: .pause, now: now))
            for current in [completed, paused] {
                let display = try current.displaySnapshot(now: now)
                XCTAssertTrue(current.run.snoozeUsed)
                XCTAssertEqual(current.reading, initial.reading, "No new provider observation was fabricated")
                XCTAssertEqual(current.reading?.provider.snoozesLeft, 1)
                XCTAssertTrue(display.railNotes.contains("Snooze used"), "\(phase), Auto \(current.run.armed)")
                XCTAssertFalse(display.railNotes.contains("1 snooze left"))
                XCTAssertEqual(display.autoOn, current.run.armed)
                XCTAssertEqual(display.deadline, before.deadline)
                XCTAssertEqual(display.goTo, before.goTo)
            }
        }
    }

    func testUnspentOfferAndHeldCaptionsPreserveKnownZeroAndUnknownProviderAllowance() throws {
        for phase in ["ACCEPT_PENDING", "PENDING_PLUG_IN"] {
            for allowance in [Int?.none, .some(0), .some(1)] {
                let value = try store(armed: false)
                let current = try observed(value, observation(phase, allowance: allowance))
                let display = try current.displaySnapshot(now: now)
                XCTAssertFalse(current.run.snoozeUsed)
                XCTAssertFalse(display.railNotes.contains("Snooze used"))
                XCTAssertEqual(display.railNotes.contains("1 snooze left"), allowance == 1)
                XCTAssertEqual(display.railNotes.contains("No snoozes left"), allowance == 0)
                XCTAssertEqual(current.reading?.provider.snoozesLeft, allowance)
            }
        }
    }

    func testSpentAutoHistoryDoesNotReplaceFreshHeldProviderManualSnoozeAllowance() throws {
        for armed in [false, true] {
            let value = try store(armed: armed)
            let evidence = try observation("PENDING_PLUG_IN", allowance: 1)
            let initial = try observed(value, evidence)
            let first = try owner(value.claim(origin: XCTUnwrap(initial.renderedOrigin), action: .snooze, now: now))
            XCTAssertTrue(try value.validatePreflight(owner: first, observation: evidence, now: now))
            _ = try admitted(value, first, .snooze)
            _ = try XCTUnwrap(value.commitOutcome(owner: first, outcome: .success, now: now))
            let refreshed = try observed(value, evidence, at: now.addingTimeInterval(1))
            let display = try refreshed.displaySnapshot(now: now.addingTimeInterval(1))
            XCTAssertTrue(refreshed.run.snoozeUsed)
            XCTAssertEqual(refreshed.run.armed, armed)
            XCTAssertEqual(refreshed.reading?.provider.snoozesLeft, 1)
            XCTAssertTrue(display.railNotes.contains("Snooze used"))
            XCTAssertTrue(display.keys.contains(where: { $0.command == "snooze" }))
            let manual = try owner(value.claim(origin: XCTUnwrap(refreshed.renderedOrigin),
                action: .snooze, cause: .manual, now: now.addingTimeInterval(1)))
            XCTAssertEqual(manual.cause, .manual)
        }
    }

    func testPauseRevokesAutomaticAdmissionWhileOperationExists() throws {
        let value = try store()
        let evidence = try observation()
        let initial = try observed(value, evidence)
        let operation = try owner(value.claim(origin: XCTUnwrap(initial.renderedOrigin), action: .accept, cause: .autoStep, now: now))
        _ = try XCTUnwrap(value.edit(expected: initial.settingsOrigin, edit: .pause, now: now))
        XCTAssertFalse(try value.validatePreflight(owner: operation, observation: evidence, now: now))
        XCTAssertNil(try value.requestCredential(authority: .operation(operation), purpose: .mutation(.accept), now: now))
    }

    func testPreflightRejectsReplacementOfferWithoutSubstitution() throws {
        let value = try store()
        let initial = try observed(value, observation())
        let operation = try owner(value.claim(origin: XCTUnwrap(initial.renderedOrigin), action: .accept, now: now))
        XCTAssertFalse(try value.validatePreflight(owner: operation, observation: observation(token: "new-offer"), now: now))
        XCTAssertNil(try value.requestCredential(authority: .operation(operation), purpose: .mutation(.accept), now: now))
    }

    func testRenderedJoinCannotTurnIntoResumeWhenFreshQueueAppears() throws {
        let value = try store(armed: false)
        let initial = try observed(value, observation("NOT_QUEUED", ids: []))
        let operation = try owner(value.claimAuto(origin: XCTUnwrap(initial.renderedOrigin), desired: .join, now: now))
        XCTAssertFalse(try value.validatePreflight(owner: operation, observation: observation("WAITING"), now: now))
        XCTAssertFalse(try value.snapshot(now: now).run.armed)
    }

    func testAdmittedUncertaintyRequiresReadBegunAfterFenceAndRejectsLateSuccess() throws {
        let value = try store()
        let evidence = try observation()
        let initial = try observed(value, evidence)
        let operation = try owner(value.claim(origin: XCTUnwrap(initial.renderedOrigin), action: .accept, now: now))
        XCTAssertTrue(try value.validatePreflight(owner: operation, observation: evidence, now: now))
        _ = try admitted(value, operation, .accept)
        let earlyTime = now.addingTimeInterval(1)
        let earlyRead = try XCTUnwrap(value.beginRead(expected: value.snapshot(now: earlyTime).context, now: earlyTime))
        _ = try value.commitOutcome(owner: operation, outcome: .uncertain, now: now.addingTimeInterval(2))
        XCTAssertNil(try value.commitOutcome(owner: operation, outcome: .success, now: now.addingTimeInterval(3)))
        let earlyCommit = try XCTUnwrap(value.commitObservation(owner: earlyRead, observation: evidence,
            observedAt: now.addingTimeInterval(3), now: now.addingTimeInterval(3)))
        XCTAssertEqual(earlyCommit.operation?.stage, .uncertain)
        XCTAssertEqual(try earlyCommit.displaySnapshot(now: now.addingTimeInterval(3)).autoControl, .stop)
        let reconciled = try observed(value, evidence, at: now.addingTimeInterval(4))
        XCTAssertNil(reconciled.operation)
        XCTAssertNotEqual(reconciled.renderedOrigin, initial.renderedOrigin)
    }

    func testLeaseExpiryPreservesUncertainOperationAndOriginalObservedTime() throws {
        let value = try store()
        let evidence = try observation()
        let initial = try observed(value, evidence)
        let operation = try owner(value.claim(origin: XCTUnwrap(initial.renderedOrigin), action: .accept, now: now))
        XCTAssertTrue(try value.validatePreflight(owner: operation, observation: evidence, now: now))
        _ = try admitted(value, operation, .accept)
        let expired = try value.snapshot(now: now.addingTimeInterval(121))
        XCTAssertEqual(expired.operation?.stage, .uncertain)
        XCTAssertEqual(expired.reading?.observedAt, initial.reading?.observedAt)
        XCTAssertTrue(try expired.displaySnapshot(now: now.addingTimeInterval(121)).keys.isEmpty)
    }

    func testReadAuthorityCannotAdmitMutationAndPreparedCookieCannotSurviveRoll() throws {
        let value = try store()
        let read = try XCTUnwrap(value.beginRead(expected: value.snapshot(now: now).context, now: now))
        XCTAssertNil(try value.requestCredential(authority: .read(read), purpose: .mutation(.accept), now: now))
        let credential = try XCTUnwrap(value.requestCredential(authority: .read(read), purpose: .status, now: now))
        let admission = try XCTUnwrap(value.authorizeAndStart(credential: credential, purpose: .status, now: now) { _ in })
        XCTAssertTrue(try value.commitResponse(admission: admission, metadata: CpResponseMetadata(status: 200, cookie: "rolled"), now: now))
        var starts = 0
        XCTAssertNil(try value.authorizeAndStart(credential: credential, purpose: .status, now: now) { _ in starts += 1 })
        XCTAssertEqual(starts, 0)
    }

    func testSupersededReadCanRollMatchingCookieButCannotExpireOrPublishNewerRead() throws {
        let value = try store()
        let a = try XCTUnwrap(value.beginRead(expected: value.snapshot(now: now).context, now: now))
        let credential = try XCTUnwrap(value.requestCredential(authority: .read(a), purpose: .status, now: now))
        let admission = try XCTUnwrap(value.authorizeAndStart(credential: credential, purpose: .status, now: now) { _ in })
        let b = try XCTUnwrap(value.beginRead(expected: value.snapshot(now: now).context, now: now))
        XCTAssertTrue(try value.commitResponse(admission: admission, metadata: CpResponseMetadata(status: 401, cookie: "rolled"), now: now))
        let current = try value.snapshot(now: now)
        XCTAssertFalse(current.session.expired)
        XCTAssertEqual(current.session.token, "rolled")
        XCTAssertEqual(current.activeRead, b)
        XCTAssertNil(try value.failRead(owner: a, message: "old failure", now: now))
    }

    func testSameAccountReauthenticationRetiresAllOldRenderedAuthority() throws {
        let value = try store()
        let old = try observed(value, observation())
        let attempt = try XCTUnwrap(value.beginSignIn(expected: old.settingsOrigin, now: now))
        _ = try XCTUnwrap(value.replaceSession(owner: attempt, candidate: CpStoreFixture.session, now: now))
        XCTAssertEqual(try value.claim(origin: XCTUnwrap(old.renderedOrigin), action: .accept, now: now), .rejected(.detailsChanged))
    }

    func testCandidateCookieIsIsolatedUntilOwnedProfileAndRenewComplete() throws {
        let value = try store()
        let before = try value.snapshot(now: now)
        let attempt = try XCTUnwrap(value.beginSignIn(expected: before.settingsOrigin, now: now))
        XCTAssertTrue(try value.stageSignInCandidate(owner: attempt, token: "candidate", now: now))
        XCTAssertNil(try value.finishSignIn(owner: attempt, now: now))
        let candidate = try XCTUnwrap(value.requestCredential(authority: .signIn(attempt), purpose: .profile, now: now))
        XCTAssertEqual(candidate.token, "candidate")
        XCTAssertEqual(try value.snapshot(now: now).session.token, before.session.token)
        let profile = try XCTUnwrap(value.authorizeAndStart(credential: candidate, purpose: .profile, now: now) { _ in })
        XCTAssertTrue(try value.commitResponse(admission: profile, metadata: CpResponseMetadata(status: 200, cookie: "candidate-roll"), now: now))
        XCTAssertTrue(try value.commitCandidateProfile(admission: profile, userID: before.session.userId,
            email: "updated@example.invalid", now: now))
        let renew = try XCTUnwrap(value.requestCredential(authority: .signIn(attempt), purpose: .renew, now: now))
        XCTAssertEqual(renew.token, "candidate-roll")
        let renewed = try XCTUnwrap(value.authorizeAndStart(credential: renew, purpose: .renew, now: now) { _ in })
        XCTAssertTrue(try value.commitResponse(admission: renewed, metadata: CpResponseMetadata(status: 200, cookie: "final"), now: now))
        let completed = try XCTUnwrap(value.finishSignIn(owner: attempt, now: now))
        XCTAssertEqual(completed.session.token, "final")
        XCTAssertEqual(completed.session.email, "updated@example.invalid")
        XCTAssertEqual(completed.location, before.location)
        XCTAssertTrue(completed.run.armed)
        XCTAssertNotEqual(completed.context.accountGeneration, before.context.accountGeneration)
    }

    func testSupersededCandidateCannotRollOrPublishIntoNewAttempt() throws {
        let value = try store()
        let context = try value.snapshot(now: now)
        let a = try XCTUnwrap(value.beginSignIn(expected: context.settingsOrigin, now: now))
        XCTAssertTrue(try value.stageSignInCandidate(owner: a, token: "a", now: now))
        let credential = try XCTUnwrap(value.requestCredential(authority: .signIn(a), purpose: .profile, now: now))
        let admission = try XCTUnwrap(value.authorizeAndStart(credential: credential, purpose: .profile, now: now) { _ in })
        let b = try XCTUnwrap(value.beginSignIn(expected: context.settingsOrigin, now: now))
        XCTAssertTrue(try value.stageSignInCandidate(owner: b, token: "b", now: now))
        XCTAssertFalse(try value.commitResponse(admission: admission, metadata: CpResponseMetadata(status: 200, cookie: "old-roll"), now: now))
        XCTAssertFalse(try value.commitCandidateProfile(admission: admission, userID: 99, email: "old", now: now))
        XCTAssertNil(try value.finishSignIn(owner: a, now: now))
        XCTAssertEqual(try value.requestCredential(authority: .signIn(b), purpose: .profile, now: now)?.token, "b")
    }

    func testDiscoveryQueryAndSettingsRevisionFenceResultsAndSelection() throws {
        let value = try store()
        let context = try value.snapshot(now: now)
        let a = try XCTUnwrap(value.beginDiscovery(expected: context.settingsOrigin, now: now))
        let b = try XCTUnwrap(value.beginDiscovery(expected: context.settingsOrigin, now: now))
        XCTAssertNil(try value.requestCredential(authority: .discovery(a), purpose: .stations(CpStoreFixture.location.bounds), now: now))
        XCTAssertNotNil(try value.requestCredential(authority: .discovery(b), purpose: .stations(CpStoreFixture.location.bounds), now: now))
        _ = try value.edit(expected: context.settingsOrigin, edit: .locationName("New"), now: now)
        XCTAssertNil(try value.finishDiscovery(owner: b, location: CpStoreFixture.location, now: now))
        XCTAssertNil(try value.requestCredential(authority: .discovery(b), purpose: .stations(CpStoreFixture.location.bounds), now: now))
    }

    func testAcknowledgementPollUsesOnlyReceiptForSameOwnedMutation() throws {
        let value = try store()
        let evidence = try observation()
        let initial = try observed(value, evidence)
        let operation = try owner(value.claim(origin: XCTUnwrap(initial.renderedOrigin), action: .accept, now: now))
        XCTAssertTrue(try value.validatePreflight(owner: operation, observation: evidence, now: now))
        let receipt = try admitted(value, operation, .accept)
        XCTAssertTrue(try value.recordAcknowledgement(owner: operation, admission: receipt, id: 44, now: now))
        XCTAssertNil(try value.requestCredential(authority: .operation(operation), purpose: .acknowledgement(45), now: now))
        XCTAssertNotNil(try value.requestCredential(authority: .operation(operation), purpose: .acknowledgement(44), now: now))
        XCTAssertNil(try value.requestCredential(authority: .operation(operation), purpose: .mutation(.accept), now: now))
    }

    func testForeignQueueCannotBecomeSelectedLocationAuthority() throws {
        let value = try store(armed: false)
        let foreign = try observed(value, observation("WAITING", ids: [99]))
        let origin = try XCTUnwrap(foreign.renderedOrigin)
        XCTAssertEqual(try value.claim(origin: origin, action: .leave, now: now), .rejected(.detailsChanged))
        XCTAssertEqual(try value.claimAuto(origin: origin, desired: .resume, now: now), .rejected(.detailsChanged))
        XCTAssertTrue(try foreign.displaySnapshot(now: now).keys.isEmpty)
    }

    func testUnknownPostFenceReadingDoesNotReconcileAdmittedMutation() throws {
        let value = try store()
        let evidence = try observation()
        let initial = try observed(value, evidence)
        let operation = try owner(value.claim(origin: XCTUnwrap(initial.renderedOrigin), action: .accept, now: now))
        XCTAssertTrue(try value.validatePreflight(owner: operation, observation: evidence, now: now))
        _ = try admitted(value, operation, .accept)
        _ = try value.commitOutcome(owner: operation, outcome: .uncertain, now: now.addingTimeInterval(1))
        let unknown = try observed(value, observation("FUTURE_PHASE"), at: now.addingTimeInterval(2))
        XCTAssertEqual(unknown.operation?.stage, .uncertain)
        XCTAssertTrue(try unknown.displaySnapshot(now: now.addingTimeInterval(2)).keys.isEmpty)
    }

    func testCurrent401RetainsChosenModeAndHistoryButDeniesProviderActions() throws {
        let value = try store()
        let initial = try observed(value, observation())
        let read = try XCTUnwrap(value.beginRead(expected: initial.context, now: now))
        let credential = try XCTUnwrap(value.requestCredential(authority: .read(read), purpose: .status, now: now))
        let admission = try XCTUnwrap(value.authorizeAndStart(credential: credential, purpose: .status, now: now) { _ in })
        XCTAssertTrue(try value.commitResponse(admission: admission, metadata: CpResponseMetadata(status: 401), now: now))
        let expired = try value.snapshot(now: now)
        XCTAssertTrue(expired.session.expired)
        XCTAssertTrue(expired.run.armed)
        XCTAssertEqual(expired.run.startedAt, initial.run.startedAt)
        XCTAssertEqual(try expired.displaySnapshot(now: now).autoControl, .stop)
        XCTAssertTrue(try expired.displaySnapshot(now: now).autoOn)
        XCTAssertEqual(try value.claim(origin: XCTUnwrap(initial.renderedOrigin), action: .accept, now: now), .rejected(.detailsChanged))
        let attempt = try XCTUnwrap(value.beginSignIn(expected: expired.settingsOrigin, now: now))
        let restored = try XCTUnwrap(value.replaceSession(owner: attempt, candidate: CpStoreFixture.session, now: now))
        XCTAssertTrue(restored.run.armed)
        XCTAssertEqual(restored.run.startedAt, initial.run.startedAt)
        let pause = try XCTUnwrap(value.edit(expected: restored.settingsOrigin, edit: .pause, now: now))
        XCTAssertFalse(pause.run.armed)
        XCTAssertEqual(pause.run.startedAt, initial.run.startedAt)
    }

    func testCurrentExpiredContextAllowsPauseWithoutProviderRead() throws {
        let value = try store()
        let initial = try value.snapshot(now: now)
        let read = try XCTUnwrap(value.beginRead(expected: initial.context, now: now))
        let credential = try XCTUnwrap(value.requestCredential(authority: .read(read), purpose: .status, now: now))
        let admission = try XCTUnwrap(value.authorizeAndStart(credential: credential, purpose: .status, now: now) { _ in })
        _ = try value.commitResponse(admission: admission, metadata: CpResponseMetadata(status: 401), now: now)
        let expired = try value.snapshot(now: now)
        let result = try value.claimAuto(origin: XCTUnwrap(expired.renderedOrigin), desired: .pause, now: now)
        guard case .modeChanged(let paused) = result else { return XCTFail("Local Pause must remain available") }
        XCTAssertFalse(paused.run.armed)
        XCTAssertTrue(paused.session.expired)
    }

    func testPendingWaitingPhaseDoesNotAuthorizeOfferActions() throws {
        let value = try store()
        let initial = try observed(value, observation("PENDING", allowance: 1))
        let origin = try XCTUnwrap(initial.renderedOrigin)
        XCTAssertEqual(try value.claim(origin: origin, action: .accept, now: now), .rejected(.detailsChanged))
        XCTAssertEqual(try value.claim(origin: origin, action: .snooze, now: now), .rejected(.detailsChanged))
    }

    func testFailedReadRetiresOldActionAuthorityWithoutChangingObservedTime() throws {
        let value = try store()
        let initial = try observed(value, observation())
        let read = try XCTUnwrap(value.beginRead(expected: initial.context, now: now))
        let failed = try XCTUnwrap(value.failRead(owner: read, message: "fixture failure", now: now))
        XCTAssertEqual(failed.reading?.observedAt, initial.reading?.observedAt)
        XCTAssertTrue(try failed.displaySnapshot(now: now).keys.isEmpty)
        XCTAssertEqual(try value.claim(origin: XCTUnwrap(initial.renderedOrigin), action: .accept, now: now), .rejected(.detailsChanged))
    }

    func testSupportedExactChargingSessionCanStopWithUnknownQueue() throws {
        let value = try store()
        let evidence = try cpOwnedObservation(statusJson: "{\"user_status\":{\"charging\":{\"state\":\"CHARGING\",\"sessionId\":42}}}",
            details: CpDetailEvidence(chargingSessionID: 42,
                chargingJson: "{\"charging_status\":{\"session_id\":42,\"stop_charge_supported\":true}}"))
        let initial = try observed(value, evidence)
        XCTAssertFalse(evidence.identity.queueKnown)
        XCTAssertNotNil(try owner(value.claim(origin: XCTUnwrap(initial.renderedOrigin), action: .stop, now: now)))
    }

    func testCredentialAToBToACannotReviveOldResponseOrPreparedAdmission() throws {
        let value = try store()
        let read = try XCTUnwrap(value.beginRead(expected: value.snapshot(now: now).context, now: now))
        let original = try XCTUnwrap(value.requestCredential(authority: .read(read), purpose: .status, now: now))
        let a = try XCTUnwrap(value.authorizeAndStart(credential: original, purpose: .status, now: now) { _ in })
        XCTAssertTrue(try value.commitResponse(admission: a, metadata: CpResponseMetadata(status: 200, cookie: "B"), now: now))
        let rolled = try XCTUnwrap(value.requestCredential(authority: .read(read), purpose: .status, now: now))
        let b = try XCTUnwrap(value.authorizeAndStart(credential: rolled, purpose: .status, now: now) { _ in })
        XCTAssertTrue(try value.commitResponse(admission: b, metadata: CpResponseMetadata(status: 200, cookie: original.token), now: now))
        XCTAssertFalse(try value.commitResponse(admission: a, metadata: CpResponseMetadata(status: 401, cookie: "late"), now: now))
        var starts = 0
        XCTAssertNil(try value.authorizeAndStart(credential: original, purpose: .status, now: now) { _ in starts += 1 })
        XCTAssertEqual(starts, 0)
        XCTAssertFalse(try value.snapshot(now: now).session.expired)
        XCTAssertEqual(try value.snapshot(now: now).session.token, original.token)
    }

    func testSameAttemptRestagedCandidateRejectsOldProfileAndCookieEvenAfterTokenABA() throws {
        let value = try store()
        let attempt = try XCTUnwrap(value.beginSignIn(expected: value.snapshot(now: now).settingsOrigin, now: now))
        XCTAssertTrue(try value.stageSignInCandidate(owner: attempt, token: "A", now: now))
        let original = try XCTUnwrap(value.requestCredential(authority: .signIn(attempt), purpose: .profile, now: now))
        let a = try XCTUnwrap(value.authorizeAndStart(credential: original, purpose: .profile, now: now) { _ in })
        XCTAssertTrue(try value.stageSignInCandidate(owner: attempt, token: "B", now: now))
        XCTAssertTrue(try value.stageSignInCandidate(owner: attempt, token: "A", now: now))
        XCTAssertFalse(try value.commitResponse(admission: a, metadata: CpResponseMetadata(status: 200, cookie: "old"), now: now))
        XCTAssertFalse(try value.commitCandidateProfile(admission: a, userID: 99, email: "old", now: now))
        XCTAssertNil(try value.authorizeAndStart(credential: original, purpose: .profile, now: now) { _ in XCTFail("No retired start") })
        XCTAssertNil(try value.finishSignIn(owner: attempt, now: now))
    }

    func testOperationDetailRequestsCannotFetchForeignTargetOrRenewCredentials() throws {
        let value = try store()
        let evidence = try observation(allowance: 1)
        let operation = try owner(value.claim(origin: XCTUnwrap(observed(value, evidence).renderedOrigin), action: .snooze, now: now))
        XCTAssertNil(try value.requestCredential(authority: .operation(operation), purpose: .allowance("foreign"), now: now))
        XCTAssertNil(try value.requestCredential(authority: .operation(operation), purpose: .charging(999), now: now))
        XCTAssertNil(try value.requestCredential(authority: .operation(operation), purpose: .renew, now: now))
        XCTAssertNotNil(try value.requestCredential(authority: .operation(operation), purpose: .allowance("private-offer"), now: now))
    }

    func testSemanticallyCorruptPersistedJournalDoesNotIssueAuthority() throws {
        let directory = try CpStoreFixture.directory(self)
        let value = CpStateStore(directory: directory)
        _ = try value.bootstrap(legacy: CpStoreFixture.legacy, now: now)
        _ = try observed(value, observation())
        let file = directory.appendingPathComponent("cp-state.json")
        var object = try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as! [String: Any]
        var journal = object["journal"] as! [String: Any]
        var evidence = journal["observation"] as! [String: Any]
        var identity = evidence["identity"] as! [String: Any]
        identity["phase"] = "NOT_QUEUED"
        evidence["identity"] = identity
        journal["observation"] = evidence
        object["journal"] = journal
        try JSONSerialization.data(withJSONObject: object).write(to: file)
        XCTAssertThrowsError(try value.snapshot(now: now))
    }

    func testAutomaticFailureReceiptSuppressesExactTargetButAllowsReplacementWithSameDeadline() throws {
        let value = try store()
        let time = now.addingTimeInterval(181)
        let evidence = try observation(token: "A")
        let initial = try observed(value, evidence, at: time)
        let operation = try owner(value.claim(origin: XCTUnwrap(initial.renderedOrigin), action: .accept, cause: .autoStep, now: time))
        XCTAssertTrue(try value.validatePreflight(owner: operation, observation: evidence, now: time))
        _ = try admitted(value, operation, .accept, at: time)
        _ = try value.commitOutcome(owner: operation, outcome: .uncertain, now: time)
        let same = try observed(value, evidence, at: time.addingTimeInterval(1))
        XCTAssertNil(try value.autoTick(origin: XCTUnwrap(same.renderedOrigin), now: time.addingTimeInterval(1)))
        let replacement = try observed(value, observation(token: "B"), at: time.addingTimeInterval(2))
        XCTAssertNotNil(try value.autoTick(origin: XCTUnwrap(replacement.renderedOrigin), now: time.addingTimeInterval(2)))
    }

    func testKnownReplacedOfferHidesOldCountdownAndGoToInstruction() throws {
        let value = try store()
        let initial = try observed(value, observation(token: "A"))
        let operation = try owner(value.claim(origin: XCTUnwrap(initial.renderedOrigin), action: .accept, now: now))
        XCTAssertFalse(try value.validatePreflight(owner: operation, observation: observation(token: "B"), now: now))
        let display = try value.snapshot(now: now).displaySnapshot(now: now)
        XCTAssertNil(display.deadline)
        XCTAssertNil(display.goTo)
        XCTAssertTrue(display.keys.isEmpty)
    }

    func testElapsedOfferHidesProviderControlsAndInstructionButRetainsLocalPause() throws {
        let value = try store()
        _ = try observed(value, observation(allowance: 1))
        let display = try value.snapshot(now: now.addingTimeInterval(301)).displaySnapshot(now: now.addingTimeInterval(301))
        XCTAssertNil(display.deadline)
        XCTAssertNil(display.goTo)
        XCTAssertTrue(display.keys.isEmpty)
        XCTAssertEqual(display.autoControl, .stop)
    }

    func testNotificationPermissionEffectRequiresTheAcceptedCurrentChosenMode() throws {
        let value = try store()
        let initial = try value.snapshot(now: now)
        var effects = 0
        XCTAssertTrue(try value.withChosenMode(expected: initial.context) { effects += 1 })
        _ = try value.edit(expected: initial.settingsOrigin, edit: .pause, now: now)
        XCTAssertFalse(try value.withChosenMode(expected: initial.context) { effects += 1 })
        XCTAssertEqual(effects, 1)
    }

    func testCurrent401PublishesOwnedSignedOutAlertOnlyOnceAfterDurableExpiry() throws {
        let value = try store()
        let read = try XCTUnwrap(value.beginRead(expected: value.snapshot(now: now).context, now: now))
        let credential = try XCTUnwrap(value.requestCredential(authority: .read(read), purpose: .status, now: now))
        let admission = try XCTUnwrap(value.authorizeAndStart(credential: credential, purpose: .status, now: now) { _ in })
        var alerts: [CpAlert] = []
        XCTAssertTrue(try value.commitResponse(admission: admission, metadata: CpResponseMetadata(status: 401), now: now) { alert, snapshot in
            XCTAssertTrue(snapshot.session.expired); XCTAssertTrue(snapshot.run.armed)
            alerts.append(alert)
        })
        XCTAssertFalse(try value.commitResponse(admission: admission, metadata: CpResponseMetadata(status: 401), now: now) { alert, _ in alerts.append(alert) })
        XCTAssertEqual(alerts, [.signedOut])
    }

    func testAutomaticAdmittedFailurePublishesOneOperationalAlertInCurrentContext() throws {
        let value = try store()
        let evidence = try observation()
        let initial = try observed(value, evidence)
        let operation = try owner(value.claim(origin: XCTUnwrap(initial.renderedOrigin), action: .accept, cause: .autoStep, now: now))
        XCTAssertTrue(try value.validatePreflight(owner: operation, observation: evidence, now: now))
        _ = try admitted(value, operation, .accept)
        var alerts: [CpAlert] = []
        _ = try value.commitOutcome(owner: operation, outcome: .uncertain, now: now) { alert, snapshot in
            XCTAssertEqual(snapshot.operation?.stage, .uncertain)
            XCTAssertEqual(snapshot.context.accountGeneration, operation.context.accountGeneration)
            alerts.append(alert)
        }
        XCTAssertNil(try value.commitOutcome(owner: operation, outcome: .uncertain, now: now) { alert, _ in alerts.append(alert) })
        XCTAssertEqual(alerts, [.failed])
    }

    func testSameAccountReauthenticationRebasesUncertaintyWithoutRevivingOldCompletionOrAutoRetry() throws {
        let value = try store()
        let evidence = try observation()
        let initial = try observed(value, evidence)
        let operation = try owner(value.claim(origin: XCTUnwrap(initial.renderedOrigin), action: .accept, cause: .autoStep, now: now))
        XCTAssertTrue(try value.validatePreflight(owner: operation, observation: evidence, now: now))
        _ = try admitted(value, operation, .accept)
        _ = try value.commitOutcome(owner: operation, outcome: .uncertain, now: now)
        let attempt = try XCTUnwrap(value.beginSignIn(expected: value.snapshot(now: now).settingsOrigin, now: now))
        XCTAssertTrue(try value.stageSignInCandidate(owner: attempt, token: "reauthenticated", now: now))
        let profileCredential = try XCTUnwrap(value.requestCredential(authority: .signIn(attempt), purpose: .profile, now: now))
        let profile = try XCTUnwrap(value.authorizeAndStart(credential: profileCredential, purpose: .profile, now: now) { _ in })
        XCTAssertTrue(try value.commitResponse(admission: profile, metadata: CpResponseMetadata(status: 200), now: now))
        XCTAssertTrue(try value.commitCandidateProfile(admission: profile, userID: CpStoreFixture.session.userId, email: "same", now: now))
        let credential = try XCTUnwrap(value.requestCredential(authority: .signIn(attempt), purpose: .renew, now: now))
        let renew = try XCTUnwrap(value.authorizeAndStart(credential: credential, purpose: .renew, now: now) { _ in })
        XCTAssertTrue(try value.commitResponse(admission: renew, metadata: CpResponseMetadata(status: 200), now: now))
        let accepted = try XCTUnwrap(value.finishSignIn(owner: attempt, now: now))
        XCTAssertEqual(accepted.operation?.stage, .uncertain)
        XCTAssertNotEqual(accepted.operation?.owner, operation)
        XCTAssertTrue(accepted.run.armed)
        XCTAssertNil(try value.commitOutcome(owner: operation, outcome: .success, now: now))
        let reconciled = try observed(value, evidence, at: now.addingTimeInterval(181))
        XCTAssertNil(reconciled.operation)
        XCTAssertNil(try value.autoTick(origin: XCTUnwrap(reconciled.renderedOrigin), now: now.addingTimeInterval(181)))
        XCTAssertNotNil(try owner(value.claim(origin: XCTUnwrap(reconciled.renderedOrigin), action: .accept, now: now.addingTimeInterval(181))))
    }

    func testStringIdleCanJoinButMalformedStringStatesCannotProduceAuthority() throws {
        let value = try store(armed: false)
        let idle = try cpOwnedObservation(statusJson: "{\"user_status\":{\"waitlist\":{\"state\":\"NOT_QUEUED\",\"stations\":[]}}}")
        let current = try observed(value, idle)
        XCTAssertNotNil(try owner(value.claim(origin: XCTUnwrap(current.renderedOrigin), action: .join, now: now)))
        for phase in ["", "PASS", "UNKNOWN", "FUTURE_PROVIDER_PHASE"] {
            XCTAssertThrowsError(try cpOwnedObservation(statusJson: "{\"user_status\":{\"waitlist\":{\"state\":\"\(phase)\"}}}"))
        }
    }

    func testAccountSnoozedWithoutMembershipNeverInfersSelectedBuildingAuthority() throws {
        let value = try store(armed: false)
        let evidence = try cpOwnedObservation(statusJson: """
            {"user_status":{"waitlist":{"state":{"state":"PASS","startTimeUTC":999,"duration":301,"autoSnooze":true},"stations":[]}}}
            """)
        let current = try observed(value, evidence)
        XCTAssertEqual(evidence.identity.phase, "PASS")
        XCTAssertEqual(evidence.identity.stationIDs, [])
        XCTAssertEqual(try current.displaySnapshot(now: now).bigAnswer, "Snoozed")
        XCTAssertEqual(try value.snapshot(now: now).reading?.provider, evidence.provider)
        let origin = try XCTUnwrap(current.renderedOrigin)
        XCTAssertEqual(try value.claim(origin: origin, action: .unsnooze, now: now), .rejected(.detailsChanged))
        XCTAssertEqual(try value.claim(origin: origin, action: .leave, now: now), .rejected(.detailsChanged))
        XCTAssertEqual(try value.claimAuto(origin: origin, desired: .resume, now: now), .rejected(.detailsChanged))
    }

    func testSameAccountReauthenticationRetiresKnownUnsentClaimAndPreparedMutation() throws {
        for preflighted in [false, true] {
            let value = try store()
            let evidence = try observation()
            let before = try observed(value, evidence)
            let operation = try owner(value.claim(origin: XCTUnwrap(before.renderedOrigin), action: .accept, now: now))
            var preparedCredential: CpRequestCredential?
            if preflighted {
                XCTAssertTrue(try value.validatePreflight(owner: operation, observation: evidence, now: now))
                preparedCredential = try XCTUnwrap(value.requestCredential(authority: .operation(operation),
                    purpose: .mutation(.accept), now: now))
            }
            let attempt = try XCTUnwrap(value.beginSignIn(expected: value.snapshot(now: now).settingsOrigin, now: now))
            XCTAssertTrue(try value.stageSignInCandidate(owner: attempt, token: "same-account-renewed", now: now))
            let profileCredential = try XCTUnwrap(value.requestCredential(authority: .signIn(attempt), purpose: .profile, now: now))
            let profile = try XCTUnwrap(value.authorizeAndStart(credential: profileCredential, purpose: .profile, now: now) { _ in })
            XCTAssertTrue(try value.commitResponse(admission: profile, metadata: CpResponseMetadata(status: 200), now: now))
            XCTAssertTrue(try value.commitCandidateProfile(admission: profile, userID: before.session.userId,
                email: before.session.email, now: now))
            let renewCredential = try XCTUnwrap(value.requestCredential(authority: .signIn(attempt), purpose: .renew, now: now))
            let renew = try XCTUnwrap(value.authorizeAndStart(credential: renewCredential, purpose: .renew, now: now) { _ in })
            XCTAssertTrue(try value.commitResponse(admission: renew, metadata: CpResponseMetadata(status: 200), now: now))
            let accepted = try XCTUnwrap(value.finishSignIn(owner: attempt, now: now))
            XCTAssertNil(accepted.operation)
            XCTAssertNotEqual(accepted.ownershipFeedback, .noResponse)
            XCTAssertTrue(accepted.run.armed)
            XCTAssertEqual(accepted.run.snoozeUsed, before.run.snoozeUsed)
            XCTAssertFalse(try value.validatePreflight(owner: operation, observation: evidence, now: now))
            XCTAssertNil(try value.requestCredential(authority: .operation(operation), purpose: .mutation(.accept), now: now))
            if let preparedCredential {
                var starts = 0
                XCTAssertNil(try value.authorizeAndStart(credential: preparedCredential, purpose: .mutation(.accept), now: now) { _ in starts += 1 })
                XCTAssertEqual(starts, 0)
            }
            XCTAssertNil(try value.commitOutcome(owner: operation, outcome: .success, now: now))
        }
    }
}

private final class CpClaimCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    func increment() { lock.withLock { count += 1 } }
    var value: Int { lock.withLock { count } }
}
