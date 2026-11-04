import Foundation
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

/// CP's record is independent of HA and shared by the app and extension through a permanent lock.
/// The live App Group adapter and widget runtime use this record as their sole CP authority.
public struct CpStateStore: Sendable {
    private let directory: URL
    private static let readLease: TimeInterval = 60
    private static let maximumStateBytes = 256 * 1024

    private struct StoredAlerts: Codable {
        var offer: Bool
        var accepted: Bool
        var snoozed: Bool
        var second: Bool
        init(_ value: CpAlertPrefs) {
            offer = value.offer; accepted = value.accepted; snoozed = value.snoozed; second = value.second
        }
        var value: CpAlertPrefs {
            CpAlertPrefs(offer: offer, accepted: accepted, snoozed: snoozed, second: second)
        }
    }

    private struct Stored: Codable {
        var version = 2
        var session: CpSession
        var location: CpLocation?
        var runWire: String
        var alerts: StoredAlerts
        var udid: String
        var context: CpContextStamp
        var reading: CpStoredReading?
        var failure: CpStateFailure?
        var activeRead: CpReadOwner?
        var signInOwner: CpSignInOwner?
        var journal: CpActionJournal?

        init(session: CpSession, location: CpLocation?, run: CpRun, alerts: CpAlertPrefs, udid: String) {
            self.session = session; self.location = location; runWire = cpRunToWire(run)
            self.alerts = StoredAlerts(alerts); self.udid = udid
            context = CpContextStamp(accountGeneration: UUID().uuidString, selectionRevision: UUID().uuidString,
                                     runID: UUID().uuidString, modeRevision: UUID().uuidString,
                                     settingsRevision: UUID().uuidString)
            journal = CpActionJournal()
        }
        var snapshot: CpStoreSnapshot {
            var value = CpStoreSnapshot(session: session, location: location, run: cpRunFromWire(runWire), alerts: alerts.value,
                udid: udid, context: context, reading: reading, failure: failure, activeRead: activeRead)
            if let journal {
                value.renderedOrigin = CpRenderedOrigin(context: context, queueRevision: journal.queueRevision,
                    assignmentRevision: journal.assignmentRevision, actionRevision: journal.actionRevision,
                    observationID: journal.observationID)
                value.operation = journal.operation
                value.ownershipFeedback = journal.feedback
                value.providerActionable = journal.observation == nil ? nil : journal.actionable
            }
            return value
        }
        mutating func rotate(account: Bool = false, selection: Bool = false, run: Bool = false,
                             mode: Bool = false, settings: Bool = true) {
            context = CpContextStamp(
                accountGeneration: account ? UUID().uuidString : context.accountGeneration,
                selectionRevision: selection ? UUID().uuidString : context.selectionRevision,
                runID: run ? UUID().uuidString : context.runID,
                modeRevision: mode ? UUID().uuidString : context.modeRevision,
                settingsRevision: settings ? UUID().uuidString : context.settingsRevision)
        }
        mutating func retireReadings() {
            reading = nil; failure = nil; activeRead = nil
            journal = CpActionJournal()
        }
    }

    public init(directory: URL) { self.directory = directory }

    public func snapshot(now: Date = .now) throws -> CpStoreSnapshot {
        try requireFinite(now)
        return try locked {
            var stored = try read()
            if expireOperation(&stored, now: now) { try write(stored) }
            return stored.snapshot
        }
    }

    /// The marker is committed before importing. A crash in that gap requires signed-out recovery.
    public func bootstrap(legacy: CpLegacyState? = nil, now: Date = .now) throws -> CpStoreSnapshot {
        try requireFinite(now)
        return try locked {
            if try exists(file) { return try read().snapshot }
            guard try !exists(marker) else { throw CpStateStoreError.missingAuthoritativeState }
            try ensureMarker()
            let supplied = legacy?.session ?? CpSession()
            let hasCredential = supplied.userId > 0 && !supplied.token.isEmpty && supplied.renewedAt >= 0
            let session = hasCredential ? supplied : CpSession()
            let location = hasCredential && validLocation(legacy?.location) ? legacy?.location : nil
            var run = hasCredential ? validatedLegacyRun(legacy?.runWire ?? "") : CpRun()
            if session.expired || location == nil { run = cpPauseRun(run) }
            var stored = Stored(session: session, location: location, run: run,
                alerts: legacy?.alerts ?? CpAlertPrefs(),
                udid: legacy?.udid.flatMap { $0.isEmpty ? nil : $0 } ?? UUID().uuidString)
            if legacy?.pendingOperation != nil, hasCredential {
                let owner = CpOperationOwner(operationID: UUID().uuidString, claimRevision: UUID().uuidString,
                    context: stored.context, cause: .manual)
                let unknown = CpObservedIdentity(phase: "UNKNOWN", stationIDs: [], token: nil, deviceID: nil,
                    port: nil, startMs: nil, deadlineMs: nil, sessionID: nil)
                stored.journal!.operation = CpOwnedOperation(owner: owner, action: .legacy, target: unknown,
                    startedAt: now, expiresAt: now.addingTimeInterval(120), stage: .uncertain, reconciliationAfter: now)
                stored.journal!.feedback = .noResponse
            }
            try write(stored)
            return stored.snapshot
        }
    }

    /// Only an explicit recovery surface should call this; it never reimports legacy credentials.
    public func recoverSignedOut(now: Date = .now) throws -> CpStoreSnapshot {
        try requireFinite(now)
        return try locked {
            let previous = try? read()
            try ensureMarker()
            let stored = Stored(session: CpSession(), location: nil, run: CpRun(),
                alerts: previous?.alerts.value ?? CpAlertPrefs(), udid: previous?.udid ?? UUID().uuidString)
            try write(stored)
            return stored.snapshot
        }
    }

    public func beginSignIn(expected: CpSettingsOrigin, now: Date = .now) throws -> CpSignInOwner? {
        try requireFinite(now)
        return try locked {
            var stored = try read()
            guard stored.context == expected.context else { return nil }
            let owner = CpSignInOwner(accountGeneration: stored.context.accountGeneration, attemptID: UUID().uuidString)
            stored.signInOwner = owner
            stored.journal!.candidate = nil
            stored.journal!.signInOrigin = expected
            try write(stored)
            return owner
        }
    }

    public func cancelSignIn(owner: CpSignInOwner) throws {
        try locked {
            var stored = try read()
            guard stored.signInOwner == owner else { return }
            stored.signInOwner = nil; stored.journal!.candidate = nil; stored.journal!.signInOrigin = nil
            try write(stored)
        }
    }

    public func stageSignInCandidate(owner: CpSignInOwner, token: String, now: Date = .now) throws -> Bool {
        try requireFinite(now)
        return try locked {
            var stored = try read()
            guard !token.isEmpty, stored.signInOwner == owner, stored.context.accountGeneration == owner.accountGeneration,
                  stored.journal!.signInOrigin?.context == stored.context else { return false }
            stored.journal!.candidate = CpCandidateSession(owner: owner, token: token, userID: 0, email: "",
                credentialRevision: UUID().uuidString, expiresAt: now.addingTimeInterval(300))
            stored.journal!.lastAdmission = nil; stored.journal!.lastResponseStatus = nil
            try write(stored)
            return true
        }
    }

    public func commitCandidateProfile(admission: CpDispatchAdmission, userID: Int64, email: String,
                                       now: Date = .now) throws -> Bool {
        try requireFinite(now)
        return try locked {
            var stored = try read()
            guard case .signIn(let owner) = admission.authority, admission.purpose == .profile, userID > 0,
                  stored.journal!.lastAdmission == admission, (200..<300).contains(stored.journal!.lastResponseStatus ?? 0),
                  authorityCurrent(stored, authority: .signIn(owner), now: now) else { return false }
            stored.journal!.candidate!.userID = userID
            stored.journal!.candidate!.email = email
            stored.journal!.candidate!.profileVerified = true
            try write(stored)
            return true
        }
    }

    public func finishSignIn(owner: CpSignInOwner, now: Date = .now) throws -> CpStoreSnapshot? {
        try requireFinite(now)
        return try locked {
            var stored = try read()
            guard authorityCurrent(stored, authority: .signIn(owner), now: now),
                  let candidate = stored.journal!.candidate, candidate.userID > 0, candidate.profileVerified,
                  stored.journal!.lastAdmission?.authority == .signIn(owner),
                  stored.journal!.lastAdmission?.purpose == .renew,
                  (200..<300).contains(stored.journal!.lastResponseStatus ?? 0) else { return nil }
            installVerifiedSession(&stored, session: CpSession(token: candidate.token, userId: candidate.userID,
                email: candidate.email, renewedAt: try epochMilliseconds(now)), now: now)
            try write(stored)
            return stored.snapshot
        }
    }

    public func beginDiscovery(expected: CpSettingsOrigin, now: Date = .now) throws -> CpDiscoveryOwner? {
        try requireFinite(now)
        return try locked {
            var stored = try read()
            guard stored.context == expected.context, stored.session.isSignedIn else { return nil }
            let owner = CpDiscoveryOwner(settings: expected, queryID: UUID().uuidString,
                startedAt: now, expiresAt: now.addingTimeInterval(60))
            stored.journal!.discovery = owner
            try write(stored)
            return owner
        }
    }

    public func finishDiscovery(owner: CpDiscoveryOwner, location: CpLocation,
                                now: Date = .now) throws -> CpStoreSnapshot? {
        try requireFinite(now)
        return try locked {
            var stored = try read()
            guard authorityCurrent(stored, authority: .discovery(owner), now: now), validLocation(location) else { return nil }
            let changedTarget = !sameTarget(stored.location, location)
            stored.location = location
            if changedTarget {
                stored.runWire = cpRunToWire(cpPauseRun(cpRunFromWire(stored.runWire)))
                stored.rotate(selection: true, run: true, mode: true)
                stored.retireReadings(); stored.signInOwner = nil
            } else { stored.rotate(); stored.journal!.discovery = nil }
            try write(stored)
            return stored.snapshot
        }
    }

    public func recordAcknowledgement(owner: CpOperationOwner, admission: CpDispatchAdmission, id: Int64,
                                      now: Date = .now) throws -> Bool {
        try requireFinite(now)
        return try locked {
            var stored = try read()
            guard id > 0, validOperation(stored, owner: owner, now: now),
                  stored.journal!.operation?.stage == .admitted,
                  stored.journal!.operation?.mutationAdmissionID == admission.id,
                  admission.authority == .operation(owner) else { return false }
            stored.journal!.operation!.acknowledgementID = id
            try write(stored)
            return true
        }
    }

    public func replaceSession(owner: CpSignInOwner, candidate: CpSession,
                               now: Date = .now) throws -> CpStoreSnapshot? {
        try requireFinite(now)
        return try locked {
            var stored = try read()
            guard stored.signInOwner == owner, stored.context.accountGeneration == owner.accountGeneration,
                  candidate.isSignedIn, candidate.userId > 0, candidate.renewedAt >= 0 else { return nil }
            installVerifiedSession(&stored, session: candidate, now: now)
            try write(stored)
            return stored.snapshot
        }
    }

    public func edit(expected: CpSettingsOrigin, edit: CpStoreEdit,
                     now: Date = .now) throws -> CpStoreSnapshot? {
        try requireFinite(now)
        return try locked {
            var stored = try read()
            switch edit {
            case .pause:
                // Read success and unrelated Settings changes do not authorize or prevent Pause.
                guard sameMode(stored.context, expected.context) else { return nil }
                var run = cpRunFromWire(stored.runWire)
                guard run.armed else { return stored.snapshot }
                run.armed = false
                stored.runWire = cpRunToWire(run)
                stored.rotate(mode: true)
                if let operation = stored.journal?.operation, operation.owner.cause != .manual {
                    if operation.stage == .admitted {
                        stored.journal!.operation!.stage = .uncertain
                        stored.journal!.operation!.reconciliationAfter = now
                        stored.journal!.feedback = .noResponse
                    } else if operation.stage != .uncertain {
                        stored.journal!.operation = nil; stored.journal!.feedback = .detailsChanged
                    }
                }
            default:
                guard stored.context == expected.context else { return nil }
                switch edit {
                case .location(let location):
                    guard validLocation(location) else { return nil }
                    guard stored.location != location else { return stored.snapshot }
                    let changedTarget = !sameTarget(stored.location, location)
                    stored.location = location
                    if changedTarget {
                        stored.runWire = cpRunToWire(cpPauseRun(cpRunFromWire(stored.runWire)))
                        stored.rotate(selection: true, run: true, mode: true)
                        stored.retireReadings()
                        stored.signInOwner = nil
                    } else { stored.rotate() }
                case .locationName(let name):
                    guard let location = stored.location else { return nil }
                    guard location.label != name else { return stored.snapshot }
                    stored.location = CpLocation(name: location.name, address: location.address,
                        deviceIds: location.deviceIds, bounds: location.bounds,
                        city: location.city, state: location.state, label: name)
                    stored.rotate()
                case .signOut:
                    stored.session = CpSession(); stored.location = nil; stored.runWire = cpRunToWire(CpRun())
                    stored.rotate(account: true, selection: true, run: true, mode: true)
                    stored.retireReadings()
                    stored.signInOwner = nil
                case .alert(let key, let on):
                    switch key {
                    case .offer: stored.alerts.offer = on
                    case .accepted: stored.alerts.accepted = on
                    case .snoozed: stored.alerts.snoozed = on
                    case .second: stored.alerts.second = on
                    }
                    stored.rotate()
                case .pause: break
                }
            }
            try write(stored)
            return stored.snapshot
        }
    }

    public func beginRead(expected: CpContextStamp, now: Date = .now) throws -> CpReadOwner? {
        try requireFinite(now)
        return try locked {
            var stored = try read()
            guard stored.context == expected, stored.session.isSignedIn else { return nil }
            let expiry = now.addingTimeInterval(Self.readLease)
            guard expiry.timeIntervalSinceReferenceDate.isFinite,
                  expiry.timeIntervalSince(now) == Self.readLease else { throw CpStateStoreError.invalidClock }
            let owner = CpReadOwner(accountGeneration: stored.context.accountGeneration,
                selectionRevision: stored.context.selectionRevision, readID: UUID().uuidString,
                startedAt: now, expiresAt: expiry)
            stored.activeRead = owner
            try write(stored)
            return owner
        }
    }

    public func commitRead(owner: CpReadOwner, provider: CpProviderReading, observedAt: Date,
                           now: Date = .now) throws -> CpStoreSnapshot? {
        try requireFinite(now)
        try requireFinite(observedAt)
        return try locked {
            var stored = try read()
            guard matches(stored, owner: owner, now: now),
                  observedAt >= owner.startedAt, observedAt <= now else { return nil }
            stored.reading = CpStoredReading(provider: provider, observedAt: observedAt)
            stored.failure = nil; stored.activeRead = nil
            try write(stored)
            return stored.snapshot
        }
    }

    public func failRead(owner: CpReadOwner, message: String, now: Date = .now) throws -> CpStoreSnapshot? {
        try requireFinite(now)
        return try locked {
            var stored = try read()
            guard matches(stored, owner: owner, now: now) else { return nil }
            stored.failure = CpStateFailure(message: message, attemptedAt: now)
            stored.activeRead = nil
            stored.journal!.actionable = false
            stored.journal!.actionRevision = UUID().uuidString
            try write(stored)
            return stored.snapshot
        }
    }

    private func matches(_ stored: Stored, owner: CpReadOwner, now: Date) -> Bool {
        stored.activeRead == owner && stored.context.accountGeneration == owner.accountGeneration &&
            stored.context.selectionRevision == owner.selectionRevision &&
            owner.startedAt <= now && now < owner.expiresAt
    }

    public func commitObservation(owner: CpReadOwner, observation: CpObservation, observedAt: Date,
                                  now: Date = .now) throws -> CpStoreSnapshot? {
        try requireFinite(now); try requireFinite(observedAt)
        return try locked {
            var stored = try read()
            _ = expireOperation(&stored, now: now)
            guard matches(stored, owner: owner, now: now), observedAt >= owner.startedAt, observedAt <= now else { return nil }
            var journal = stored.journal!
            let old = journal.observation?.identity
            if old?.stationIDs != observation.identity.stationIDs || old?.queued != observation.identity.queued {
                journal.queueRevision = UUID().uuidString
            }
            if old != observation.identity { journal.assignmentRevision = UUID().uuidString }
            journal.observation = observation
            journal.observationID = UUID().uuidString
            if let operation = journal.operation, operation.stage == .uncertain,
               let fence = operation.reconciliationAfter, owner.startedAt > fence,
               observation.identity.queueKnown || observation.identity.sessionID != nil {
                journal.operation = nil
            }
            journal.actionable = journal.operation == nil &&
                ((observation.identity.queueKnown && selectedQueue(stored, observation: observation)) ||
                    observation.provider.charging?.canStop == true)
            if journal.operation == nil {
                journal.actionRevision = UUID().uuidString
                journal.feedback = nil
            }
            stored.journal = journal
            stored.reading = CpStoredReading(provider: observation.provider, observedAt: observedAt)
            stored.failure = nil; stored.activeRead = nil
            try write(stored)
            return stored.snapshot
        }
    }

    public func claim(origin: CpRenderedOrigin, action: CpOwnedAction, cause: CpOperationCause = .manual,
                      now: Date = .now) throws -> CpClaimResult {
        try requireFinite(now)
        return try locked {
            var stored = try read()
            _ = expireOperation(&stored, now: now)
            let result = claim(&stored, origin: origin, action: action, cause: cause, now: now)
            try write(stored)
            return result
        }
    }

    public func claimAuto(origin: CpRenderedOrigin, desired: CpDesiredAutoAction,
                          now: Date = .now) throws -> CpClaimResult {
        if desired == .pause {
            guard let value = try edit(expected: CpSettingsOrigin(context: origin.context), edit: .pause, now: now) else {
                return .rejected(.detailsChanged)
            }
            return .modeChanged(value)
        }
        return try claim(origin: origin, action: desired == .join ? .join : .resume, cause: .explicitAuto, now: now)
    }

    public func validatePreflight(owner: CpOperationOwner, observation: CpObservation,
                                  now: Date = .now) throws -> Bool {
        try requireFinite(now)
        return try locked {
            var stored = try read()
            _ = expireOperation(&stored, now: now)
            guard let operation = stored.journal?.operation, validOperation(stored, owner: owner, now: now),
                  operation.stage == .claimed else { return false }
            guard operation.target == observation.identity,
                  operation.action == .stop || selectedQueue(stored, observation: observation),
                  permits(operation.action, observation: observation, now: now) else {
                stored.journal!.operation = nil; stored.journal!.actionable = false
                stored.journal!.feedback = operation.target.sessionID != observation.identity.sessionID ? .sessionChanged : .offerChanged
                try write(stored)
                return false
            }
            stored.journal!.operation!.stage = .preflighted
            stored.journal!.observation = observation
            try write(stored)
            return true
        }
    }

    public func requestCredential(authority: CpRequestAuthority, purpose: CpRequestPurpose,
                                  now: Date = .now) throws -> CpRequestCredential? {
        try requireFinite(now)
        return try locked {
            var stored = try read()
            if expireOperation(&stored, now: now) { try write(stored) }
            return credential(stored, authority: authority, purpose: purpose, now: now)
        }
    }

    public func authorizeAndStart(credential: CpRequestCredential, purpose: CpRequestPurpose,
                                  now: Date = .now,
                                  synchronousStart: (CpDispatchAdmission) -> Void) throws -> CpDispatchAdmission? {
        try requireFinite(now)
        return try locked {
            var stored = try read()
            if expireOperation(&stored, now: now) { try write(stored) }
            guard self.credential(stored, authority: credential.authority, purpose: purpose, now: now) == credential else { return nil }
            let admission = CpDispatchAdmission(id: UUID().uuidString, authority: credential.authority,
                credentialRevision: credential.revision, purpose: purpose, startedAt: now)
            if case .mutation = purpose {
                stored.journal!.operation!.stage = .admitted
                stored.journal!.operation!.mutationAdmissionID = admission.id
            }
            stored.journal!.lastAdmission = admission
            stored.journal!.lastResponseStatus = nil
            try write(stored)
            // The caller supplies a previously prepared task; this synchronous resume is the dispatch boundary.
            synchronousStart(admission)
            return admission
        }
    }

    public func commitResponse(admission: CpDispatchAdmission, metadata: CpResponseMetadata,
                               now: Date = .now,
                               synchronousAlert: (CpAlert, CpStoreSnapshot) -> Void = { _, _ in }) throws -> Bool {
        try requireFinite(now)
        return try locked {
            var stored = try read()
            guard stored.journal?.lastAdmission == admission,
                  authorityAccount(admission.authority) == stored.context.accountGeneration else { return false }
            if case .signIn(let owner) = admission.authority {
                guard authorityCurrent(stored, authority: .signIn(owner), now: now),
                      stored.journal!.candidate?.credentialRevision == admission.credentialRevision else { return false }
                if let cookie = metadata.cookie, !cookie.isEmpty, cookie != stored.journal!.candidate!.token {
                    stored.journal!.candidate!.token = cookie
                    stored.journal!.candidate!.credentialRevision = UUID().uuidString
                }
                stored.journal!.lastResponseStatus = metadata.status
                try write(stored)
                return true
            }
            guard admission.credentialRevision == stored.journal?.credentialRevision else { return false }
            stored.journal!.lastResponseStatus = metadata.status
            var changed = false
            var expiredNow = false
            if let cookie = metadata.cookie, !cookie.isEmpty, cookie != stored.session.token {
                stored.session.token = cookie; stored.journal!.credentialRevision = UUID().uuidString
                changed = true
            }
            if metadata.status == 401, authorityCurrent(stored, authority: admission.authority, now: now) {
                stored.session.expired = true
                stored.journal!.actionable = false
                stored.journal!.actionRevision = UUID().uuidString
                stored.journal!.credentialRevision = UUID().uuidString
                stored.activeRead = nil
                if stored.journal!.operation?.stage == .admitted {
                    stored.journal!.operation!.stage = .uncertain
                    stored.journal!.operation!.reconciliationAfter = now
                    stored.journal!.feedback = .noResponse
                    if let operation = stored.journal!.operation { parkAutomaticFailure(&stored, operation: operation) }
                }
                changed = true
                expiredNow = true
            }
            if changed || stored.journal!.lastResponseStatus != nil { try write(stored) }
            if expiredNow { synchronousAlert(.signedOut, stored.snapshot) }
            return true
        }
    }

    public func commitOutcome(owner: CpOperationOwner, outcome: CpOperationOutcome,
                              now: Date = .now,
                              synchronousAlert: (CpAlert, CpStoreSnapshot) -> Void = { _, _ in }) throws -> CpStoreSnapshot? {
        try requireFinite(now)
        return try locked { () -> CpStoreSnapshot? in
            var stored = try read()
            if expireOperation(&stored, now: now) { try write(stored) }
            guard validOperation(stored, owner: owner, now: now),
                  let operation = stored.journal?.operation, operation.stage != .uncertain else { return nil }
            switch outcome {
            case .uncertain:
                guard operation.stage == .admitted else { return nil }
                stored.journal!.operation!.stage = .uncertain
                stored.journal!.operation!.reconciliationAfter = now
                stored.journal!.feedback = .noResponse
                parkAutomaticFailure(&stored, operation: operation)
            case .success:
                guard operation.stage == .admitted || (operation.action == .resume && operation.stage == .preflighted) else { return nil }
                var run = cpRunFromWire(stored.runWire)
                if operation.action == .snooze { run.snoozeUsed = true }
                run = cpAfterManual(run, .accept, true)
                if operation.owner.cause == .explicitAuto {
                    run = operation.action == .join
                        ? cpArmForCommand(run, .join, autoRun: true, now: try epochMilliseconds(now))
                        : cpResumeRun(run, stored.journal!.observation?.provider.snoozesLeft, try epochMilliseconds(now))
                    stored.rotate(mode: true)
                }
                stored.runWire = cpRunToWire(run)
                stored.journal!.operation = nil; stored.journal!.feedback = nil
                stored.journal!.autoFailureTarget = nil
            case .refused:
                stored.journal!.operation = nil; stored.journal!.feedback = .unavailable
                parkAutomaticFailure(&stored, operation: operation)
            case .cancelledBeforeAdmission:
                guard operation.stage != .admitted else { return nil }
                stored.journal!.operation = nil; stored.journal!.feedback = .detailsChanged
                parkAutomaticFailure(&stored, operation: operation)
            }
            stored.journal!.actionable = false
            try write(stored)
            if case .success = outcome, operation.owner.cause == .autoStep {
                if operation.action == .accept { synchronousAlert(.accepted, stored.snapshot) }
                if operation.action == .snooze { synchronousAlert(.snoozed, stored.snapshot) }
            } else if operation.owner.cause == .autoStep {
                switch outcome {
                case .uncertain, .refused: synchronousAlert(.failed, stored.snapshot)
                default: break
                }
            }
            return stored.snapshot
        }
    }

    /// The decision and local history publication occur under the same owner as request admission.
    public func autoTick(origin: CpRenderedOrigin, now: Date = .now,
                         synchronousAlert: (CpAlert, CpStoreSnapshot) -> Void = { _, _ in }) throws -> CpOperationOwner? {
        try requireFinite(now)
        return try locked {
            var stored = try read()
            guard sameMode(stored.context, origin.context), stored.session.isSignedIn, !stored.session.joinExpired,
                  stored.journal!.operation == nil, stored.journal!.actionable,
                  stored.snapshot.renderedOrigin == origin, let observation = stored.journal!.observation else { return nil }
            var run = cpRunFromWire(stored.runWire)
            guard run.armed else { return nil }
            if let failedTarget = stored.journal!.autoFailureTarget {
                if failedTarget == observation.identity { return nil }
                stored.journal!.autoFailureTarget = nil
                run = cpAfterManual(run, .accept, true)
            }
            if observation.identity.phase != "ACCEPT_PENDING" { run.offerPushed = false }
            let step = cpAutoDecide(run, state: observation.identity.phase, untilMs: observation.identity.deadlineMs,
                snoozesLeft: observation.provider.snoozesLeft, charging: observation.identity.sessionID != nil,
                now: try epochMilliseconds(now))
            var alert: CpAlert?
            switch step {
            case .accept:
                if case .claimed(let owner) = claim(&stored, origin: origin, action: .accept, cause: .autoStep, now: now) {
                    try write(stored); return owner
                }
            case .snooze:
                if case .claimed(let owner) = claim(&stored, origin: origin, action: .snooze, cause: .autoStep, now: now) {
                    try write(stored); return owner
                }
            case .alert(let kind, let updated): run = updated; alert = kind
            case .done:
                run.armed = false; stored.rotate(mode: true); alert = .done
            case .wakeAt:
                if observation.identity.phase == "ACCEPT_PENDING", !run.offerPushed {
                    run.offerPushed = true; alert = run.snoozeUsed ? .secondOffer : .offer
                }
            case .idle: break
            }
            stored.runWire = cpRunToWire(run)
            try write(stored)
            if let alert { synchronousAlert(alert, stored.snapshot) }
            return nil
        }
    }

    public func recordFeedback(origin: CpRenderedOrigin, feedback: CpFeedback, now: Date = .now) throws {
        try requireFinite(now)
        try locked {
            var stored = try read()
            guard sameScope(stored.context, origin.context) else { return }
            stored.journal!.feedback = feedback
            try write(stored)
        }
    }

    /// A later permission/navigation effect belongs only to the mode actually accepted by that action.
    public func withChosenMode(expected: CpContextStamp, synchronousEffect: () -> Void) throws -> Bool {
        try locked {
            let stored = try read()
            guard sameMode(stored.context, expected), cpRunFromWire(stored.runWire).armed else { return false }
            synchronousEffect()
            return true
        }
    }

    private func claim(_ stored: inout Stored, origin: CpRenderedOrigin, action: CpOwnedAction,
                       cause: CpOperationCause, now: Date) -> CpClaimResult {
        let journal = stored.journal!
        guard stored.session.isSignedIn, !stored.session.joinExpired, stored.location != nil,
              sameScope(stored.context, origin.context), journal.queueRevision == origin.queueRevision,
              journal.assignmentRevision == origin.assignmentRevision, journal.actionRevision == origin.actionRevision,
              journal.observationID == origin.observationID, origin.observationID != nil, journal.actionable,
              journal.operation == nil, let observation = journal.observation else { return .rejected(.detailsChanged) }
        if cause != .manual {
            guard sameMode(stored.context, origin.context), cause != .autoStep || cpRunFromWire(stored.runWire).armed else {
                return .rejected(.detailsChanged)
            }
        }
        guard action == .stop || selectedQueue(stored, observation: observation),
              permits(action, observation: observation, now: now) else { return .rejected(.detailsChanged) }
        let owner = CpOperationOwner(operationID: UUID().uuidString, claimRevision: UUID().uuidString,
            context: stored.context, cause: cause)
        stored.journal!.actionRevision = UUID().uuidString
        stored.journal!.actionable = false
        stored.journal!.feedback = nil
        stored.journal!.operation = CpOwnedOperation(owner: owner, action: action, target: observation.identity,
            startedAt: now, expiresAt: now.addingTimeInterval(120), stage: .claimed)
        return .claimed(owner)
    }

    private func sameScope(_ current: CpContextStamp, _ expected: CpContextStamp) -> Bool {
        current.accountGeneration == expected.accountGeneration && current.selectionRevision == expected.selectionRevision &&
            current.runID == expected.runID
    }

    private func installVerifiedSession(_ stored: inout Stored, session: CpSession, now: Date) {
        let sameAccount = stored.session.userId == session.userId && session.userId > 0
        let previous = sameAccount ? stored.journal?.operation : nil
        let failedTarget = sameAccount ? stored.journal?.autoFailureTarget : nil
        if !sameAccount { stored.location = nil; stored.runWire = cpRunToWire(CpRun()) }
        stored.session = session
        stored.rotate(account: true, selection: true, run: true, mode: true)
        stored.retireReadings(); stored.signInOwner = nil
        stored.journal!.autoFailureTarget = failedTarget
        if let previous, previous.stage == .admitted || previous.stage == .uncertain {
            // A new cookie retires old completions, but does not establish a remote command result.
            let owner = CpOperationOwner(operationID: UUID().uuidString, claimRevision: UUID().uuidString,
                context: stored.context, cause: previous.owner.cause)
            let rebased = CpOwnedOperation(owner: owner, action: previous.action, target: previous.target,
                startedAt: now, expiresAt: now.addingTimeInterval(120), stage: .uncertain,
                reconciliationAfter: now, mutationAdmissionID: previous.mutationAdmissionID)
            stored.journal!.operation = rebased; stored.journal!.feedback = .noResponse
            parkAutomaticFailure(&stored, operation: rebased)
        }
    }

    private func validOperation(_ stored: Stored, owner: CpOperationOwner, now: Date) -> Bool {
        guard let operation = stored.journal?.operation, operation.owner == owner,
              sameScope(stored.context, owner.context), now >= operation.startedAt, now < operation.expiresAt else { return false }
        return owner.cause == .manual || sameMode(stored.context, owner.context)
    }

    private func expireOperation(_ stored: inout Stored, now: Date) -> Bool {
        guard let operation = stored.journal?.operation, operation.stage != .uncertain, now >= operation.expiresAt else { return false }
        stored.journal!.actionable = false
        if operation.stage == .admitted {
            stored.journal!.operation!.stage = .uncertain
            stored.journal!.operation!.reconciliationAfter = now
            stored.journal!.feedback = .noResponse
        } else {
            stored.journal!.operation = nil; stored.journal!.feedback = .detailsChanged
        }
        parkAutomaticFailure(&stored, operation: operation)
        return true
    }

    private func parkAutomaticFailure(_ stored: inout Stored, operation: CpOwnedOperation) {
        guard operation.owner.cause == .autoStep else { return }
        stored.journal!.autoFailureTarget = operation.target
        stored.runWire = cpRunToWire(cpRecordAutoFailure(cpRunFromWire(stored.runWire),
            operation.target.phase, operation.target.deadlineMs, "No automatic retry · Use a current manual action"))
    }

    private func permits(_ action: CpOwnedAction, observation: CpObservation, now: Date) -> Bool {
        let identity = observation.identity
        if action == .stop { return identity.sessionID != nil && observation.provider.charging?.canStop == true }
        guard identity.queueKnown else { return false }
        switch action {
        case .join: return identity.phase == "NOT_QUEUED" && identity.sessionID == nil
        case .resume: return identity.queued && identity.sessionID == nil && identity.phase != "CHARGING"
        case .legacy: return false
        case .leave: return identity.queued && identity.sessionID == nil
        case .unsnooze:
            return identity.phase == "PASS" && identity.sessionID == nil &&
                identity.deadlineMs.map { $0 > 0 && Double($0) > now.timeIntervalSince1970 * 1000 } == true
        case .stop: return false // Handled independently of queue readiness above.
        case .still, .done:
            return ["CHARGING_FAULT", "DIB_PLUG_OUT"].contains(identity.phase) && identity.token != nil &&
                identity.deadlineMs.map { Double($0) > now.timeIntervalSince1970 * 1000 } == true
        case .accept, .snooze:
            guard let deadline = identity.deadlineMs, Double(deadline) > now.timeIntervalSince1970 * 1000,
                  identity.deviceID != nil, identity.port != nil, identity.token != nil else { return false }
            if action == .accept { return identity.phase == "ACCEPT_PENDING" }
            return ["ACCEPT_PENDING", "PENDING_PLUG_IN", "DIB_PENDING_PLUG_IN"].contains(identity.phase) &&
                (observation.provider.snoozesLeft ?? 0) > 0
        }
    }

    private func selectedQueue(_ stored: Stored, observation: CpObservation) -> Bool {
        guard let location = stored.location else { return false }
        let identity = observation.identity
        if identity.phase == "NOT_QUEUED" { return identity.stationIDs.isEmpty }
        let selected = Set(location.deviceIds)
        guard !identity.stationIDs.isEmpty, Set(identity.stationIDs).isSubset(of: selected) else { return false }
        if let device = identity.deviceID { return selected.contains(device) && identity.stationIDs.contains(device) }
        return true
    }

    private func credential(_ stored: Stored, authority: CpRequestAuthority, purpose: CpRequestPurpose,
                            now: Date) -> CpRequestCredential? {
        if case .signIn(let owner) = authority {
            guard authorityCurrent(stored, authority: authority, now: now), let candidate = stored.journal!.candidate,
                  purpose == .profile || (purpose == .renew && candidate.profileVerified && candidate.userID > 0) else { return nil }
            return CpRequestCredential(authority: .signIn(owner), revision: candidate.credentialRevision,
                token: candidate.token, userID: candidate.userID, location: nil, udid: stored.udid, target: nil)
        }
        guard stored.session.isSignedIn else { return nil }
        var target: CpObservedIdentity?
        switch authority {
        case .read(let owner):
            guard matches(stored, owner: owner, now: now), readPurpose(purpose) else { return nil }
        case .operation(let owner):
            guard validOperation(stored, owner: owner, now: now), let operation = stored.journal?.operation else { return nil }
            target = operation.target
            switch purpose {
            case .mutation(let action):
                guard action == operation.action, action != .resume, operation.stage == .preflighted,
                      operation.mutationAdmissionID == nil else { return nil }
                // Rechecked at final send admission against the same preflight target.
                guard let observation = stored.journal?.observation,
                      observation.identity == operation.target,
                      permits(action, observation: observation, now: now) else { return nil }
            case .acknowledgement(let id):
                guard operation.stage == .admitted, operation.acknowledgementID == id else { return nil }
            default:
                guard operation.stage == .claimed, readPurpose(purpose) else { return nil }
                switch purpose {
                case .status, .inline: break
                case .allowance(let token): guard token == operation.target.token else { return nil }
                case .charging(let id): guard id == operation.target.sessionID else { return nil }
                default: return nil
                }
            }
        case .discovery:
            guard authorityCurrent(stored, authority: authority, now: now), case .stations = purpose else { return nil }
        case .signIn: return nil
        }
        return CpRequestCredential(authority: authority, revision: stored.journal!.credentialRevision,
            token: stored.session.token, userID: stored.session.userId, location: stored.location, udid: stored.udid, target: target)
    }

    private func readPurpose(_ purpose: CpRequestPurpose) -> Bool {
        switch purpose {
        case .status, .inline, .allowance, .charging, .stations, .renew: true
        default: false
        }
    }

    private func authorityAccount(_ authority: CpRequestAuthority) -> String {
        switch authority {
        case .read(let owner): owner.accountGeneration
        case .operation(let owner): owner.context.accountGeneration
        case .discovery(let owner): owner.settings.context.accountGeneration
        case .signIn(let owner): owner.accountGeneration
        }
    }

    private func authorityCurrent(_ stored: Stored, authority: CpRequestAuthority, now: Date) -> Bool {
        switch authority {
        case .read(let owner): matches(stored, owner: owner, now: now)
        case .operation(let owner): validOperation(stored, owner: owner, now: now)
        case .discovery(let owner):
            stored.journal?.discovery == owner && stored.context == owner.settings.context &&
                owner.startedAt <= now && now < owner.expiresAt
        case .signIn(let owner):
            stored.signInOwner == owner && stored.context == stored.journal?.signInOrigin?.context &&
                stored.journal?.candidate?.owner == owner && now < (stored.journal?.candidate?.expiresAt ?? .distantPast)
        }
    }

    private func sameMode(_ current: CpContextStamp, _ expected: CpContextStamp) -> Bool {
        current.accountGeneration == expected.accountGeneration && current.selectionRevision == expected.selectionRevision &&
            current.runID == expected.runID && current.modeRevision == expected.modeRevision
    }

    private func sameTarget(_ lhs: CpLocation?, _ rhs: CpLocation?) -> Bool {
        switch (lhs, rhs) {
        case (nil, nil): true
        case (.some(let a), .some(let b)): Set(a.deviceIds) == Set(b.deviceIds) && a.bounds == b.bounds
        default: false
        }
    }

    private func validLocation(_ location: CpLocation?) -> Bool {
        guard let location else { return true }
        let bounds = location.bounds
        return !location.deviceIds.isEmpty && Set(location.deviceIds).count == location.deviceIds.count &&
            location.deviceIds.allSatisfy { $0 > 0 } &&
            [bounds.swLat, bounds.swLon, bounds.neLat, bounds.neLon].allSatisfy(\.isFinite) &&
            bounds.swLat <= bounds.neLat && bounds.swLon <= bounds.neLon
    }

    private func validatedLegacyRun(_ wire: String) -> CpRun {
        guard validRunWire(wire) else { return CpRun() }
        return cpRunFromWire(wire)
    }

    private func validRunWire(_ wire: String) -> Bool {
        let parts = wire.split(separator: "|", maxSplits: 7, omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 8, [parts[0], parts[1], parts[2], parts[4]].allSatisfy({ $0 == "0" || $0 == "1" }),
              let startedAt = Int64(parts[3]), startedAt >= 0,
              parts[0] != "1" || startedAt > 0 else { return false }
        if !parts[6].isEmpty {
            guard let until = Int64(parts[6]), until >= 0 else { return false }
        }
        return true
    }

    private func requireFinite(_ now: Date) throws {
        guard now.timeIntervalSinceReferenceDate.isFinite else { throw CpStateStoreError.invalidClock }
    }

    private func epochMilliseconds(_ now: Date) throws -> Int64 {
        let value = now.timeIntervalSince1970 * 1000
        guard value.isFinite, value >= 0, value < Double(Int64.max) else { throw CpStateStoreError.invalidClock }
        return Int64(value)
    }

    private var file: URL { directory.appendingPathComponent("cp-state.json") }
    private var marker: URL { directory.appendingPathComponent("cp-state.initialized") }

    private func read() throws -> Stored {
        guard try exists(file) else { throw CpStateStoreError.missingAuthoritativeState }
        let data = try readRegularFile(file)
        struct Header: Decodable { let version: Int }
        let version = try JSONDecoder().decode(Header.self, from: data).version
        guard version == 2 else { throw CpStateStoreError.unsupportedVersion }
        var stored = try JSONDecoder().decode(Stored.self, from: data)
        let context = stored.context
        guard [context.accountGeneration, context.selectionRevision, context.runID, context.modeRevision,
               context.settingsRevision].allSatisfy({ UUID(uuidString: $0) != nil }),
              !stored.udid.isEmpty, validLocation(stored.location), validRunWire(stored.runWire),
              // Expired credentials deny dispatch; verified current expiry does not erase chosen mode.
              !cpRunFromWire(stored.runWire).armed ||
                (stored.session.userId > 0 && !stored.session.token.isEmpty && stored.location != nil),
              stored.session.renewedAt >= 0,
              (stored.session.userId == 0 && stored.session.token.isEmpty) ||
                (stored.session.userId > 0 && !stored.session.token.isEmpty) else {
            throw CpStateStoreError.corrupt
        }
        if let reading = stored.reading { try requireFinite(reading.observedAt) }
        if let failure = stored.failure { try requireFinite(failure.attemptedAt) }
        if let owner = stored.activeRead {
            try requireFinite(owner.startedAt); try requireFinite(owner.expiresAt)
            guard UUID(uuidString: owner.readID) != nil,
                  owner.accountGeneration == context.accountGeneration,
                  owner.selectionRevision == context.selectionRevision,
                  owner.expiresAt.timeIntervalSince(owner.startedAt) == Self.readLease else {
                throw CpStateStoreError.corrupt
            }
        }
        if let owner = stored.signInOwner {
            guard owner.accountGeneration == context.accountGeneration, UUID(uuidString: owner.attemptID) != nil else {
                throw CpStateStoreError.corrupt
            }
        }
        try ensureMarker()
        if stored.journal == nil {
            stored.journal = CpActionJournal()
            try write(stored)
        }
        guard let journal = stored.journal,
              [journal.credentialRevision, journal.queueRevision, journal.assignmentRevision, journal.actionRevision]
                .allSatisfy({ UUID(uuidString: $0) != nil }),
              journal.observationID.map({ UUID(uuidString: $0) != nil }) ?? true,
              (journal.observation == nil) == (journal.observationID == nil),
              journal.observation?.valid ?? true,
              !journal.actionable || (journal.observation != nil && journal.operation == nil),
              journal.autoFailureTarget?.valid ?? true else { throw CpStateStoreError.corrupt }
        if let operation = journal.operation {
            guard UUID(uuidString: operation.owner.operationID) != nil,
                  UUID(uuidString: operation.owner.claimRevision) != nil,
                  sameScope(context, operation.owner.context), operation.target.valid,
                  operation.startedAt.timeIntervalSinceReferenceDate.isFinite,
                  operation.expiresAt.timeIntervalSince(operation.startedAt) == 120,
                  operation.mutationAdmissionID.map({ UUID(uuidString: $0) != nil }) ?? true,
                  operation.acknowledgementID.map({ $0 > 0 }) ?? true else { throw CpStateStoreError.corrupt }
            if operation.stage == .uncertain {
                guard let fence = operation.reconciliationAfter, fence.timeIntervalSinceReferenceDate.isFinite,
                      fence >= operation.startedAt else { throw CpStateStoreError.corrupt }
            } else if operation.stage == .admitted {
                guard operation.mutationAdmissionID != nil else { throw CpStateStoreError.corrupt }
            }
        }
        return stored
    }

    private func ensureMarker() throws {
        if try exists(marker) {
            _ = try readRegularFile(marker)
            try protect(marker, permissions: 0o600)
        } else {
            try replace(Data("initialized\n".utf8), at: marker)
        }
    }

    private func write(_ stored: Stored) throws {
        let data = try JSONEncoder().encode(stored)
        guard data.count <= Self.maximumStateBytes else { throw CpStateStoreError.corrupt }
        try replace(data, at: file)
    }

    /// Establish protection before the single rename commit point. Never replace the lock inode.
    private func replace(_ data: Data, at target: URL) throws {
        let staged = directory.appendingPathComponent(".cp-state-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: staged) }
        try data.write(to: staged, options: .withoutOverwriting)
        try protect(staged, permissions: 0o600)
        guard rename(staged.path, target.path) == 0 else { throw posixError() }
    }

    private func exists(_ url: URL) throws -> Bool {
        var info = stat()
        if lstat(url.path, &info) == 0 { return true }
        if errno == ENOENT { return false }
        throw posixError()
    }

    /// Bounded regular-file reads cannot hang on a FIFO or follow a replaced credential symlink.
    private func readRegularFile(_ url: URL) throws -> Data {
        let descriptor = open(url.path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK)
        guard descriptor >= 0 else { throw posixError() }
        defer { close(descriptor) }
        var info = stat()
        guard fstat(descriptor, &info) == 0 else { throw posixError() }
        guard (info.st_mode & mode_t(S_IFMT)) == mode_t(S_IFREG), info.st_size >= 0,
              info.st_size <= off_t(Self.maximumStateBytes) else { throw CpStateStoreError.corrupt }
        let expectedSize = Int(info.st_size)
        var data = Data(count: expectedSize + 1)
        var received = 0
        while received < data.count {
            let remaining = data.count - received
            let amount = data.withUnsafeMutableBytes { bytes in
                #if canImport(Darwin)
                Darwin.read(descriptor, bytes.baseAddress!.advanced(by: received), remaining)
                #else
                Glibc.read(descriptor, bytes.baseAddress!.advanced(by: received), remaining)
                #endif
            }
            if amount < 0 {
                if errno == EINTR { continue }
                throw posixError()
            }
            if amount == 0 { break }
            received += amount
        }
        guard received == expectedSize else { throw CpStateStoreError.corrupt }
        data.count = received
        return data
    }

    private func protect(_ url: URL, permissions: Int) throws {
        var attributes: [FileAttributeKey: Any] = [.posixPermissions: permissions]
        #if os(iOS)
        attributes[.protectionKey] = FileProtectionType.completeUntilFirstUserAuthentication
        #endif
        try FileManager.default.setAttributes(attributes, ofItemAtPath: url.path)
    }

    private func locked<T>(_ body: () throws -> T) throws -> T {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try protect(directory, permissions: 0o700)
        let sidecar = directory.appendingPathComponent("cp-state.lock")
        let descriptor = open(sidecar.path, O_CREAT | O_RDWR | O_NOFOLLOW, 0o600)
        guard descriptor >= 0 else { throw posixError() }
        defer { close(descriptor) }
        var info = stat()
        guard fstat(descriptor, &info) == 0 else { throw posixError() }
        guard (info.st_mode & mode_t(S_IFMT)) == mode_t(S_IFREG) else { throw CpStateStoreError.corrupt }
        try protect(sidecar, permissions: 0o600)
        while flock(descriptor, LOCK_EX) != 0 {
            if errno == EINTR { continue }
            throw posixError()
        }
        defer { _ = flock(descriptor, LOCK_UN) }
        return try body()
    }

    private func posixError() -> POSIXError {
        POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
    }
}
