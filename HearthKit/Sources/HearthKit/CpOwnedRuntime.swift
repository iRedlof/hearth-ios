import Foundation

/// The live app, extension and inert native fixture share this owned pipeline.
public struct CpOwnedRuntime: Sendable {
    public let store: CpStateStore
    public let http: CpOwnedHTTP
    private let now: @Sendable () -> Date
    private let onAlert: @Sendable (CpAlert, CpStoreSnapshot) -> Void

    public init(store: CpStateStore, directory: URL, transport: any CpOwnedTransport = CpURLSessionTransport(),
                now: @escaping @Sendable () -> Date = { .now },
                onAlert: @escaping @Sendable (CpAlert, CpStoreSnapshot) -> Void = { _, _ in }) {
        self.store = store; http = CpOwnedHTTP(store: store, directory: directory, transport: transport, onAlert: onAlert)
        self.now = now; self.onAlert = onAlert
    }

    public func refresh(runAuto: Bool = true) async throws -> CpSnapshot {
        let current = try store.snapshot(now: now())
        guard current.session.isSignedIn, current.location != nil,
              let owner = try store.beginRead(expected: current.context, now: now()) else {
            return try current.displaySnapshot(now: now())
        }
        do {
            let observation = try await fetch(authority: .read(owner), location: current.location)
            guard let observed = try store.commitObservation(owner: owner, observation: observation, observedAt: now(), now: now()) else {
                return try store.snapshot(now: now()).displaySnapshot(now: now())
            }
            if runAuto, let origin = observed.renderedOrigin,
               let operation = try store.autoTick(origin: origin, now: now(), synchronousAlert: onAlert) {
                _ = try await execute(operation)
                return try await refresh(runAuto: false)
            }
        } catch {
            _ = try store.failRead(owner: owner, message: friendlyError(error), now: now())
        }
        return try store.snapshot(now: now()).displaySnapshot(now: now())
    }

    public func refreshTimeline(runAuto: Bool = true) async throws -> [CpTimelineDisplay] {
        _ = try await refresh(runAuto: runAuto)
        let capturedAt = now()
        let captured = try store.snapshot(now: capturedAt)
        return try captured.timelineDisplays(now: capturedAt)
    }

    public func perform(origin: CpRenderedOrigin, action: CpOwnedAction) async throws -> CpSnapshot {
        try await act(origin: origin, claim: store.claim(origin: origin, action: action, now: now()))
    }
    public func setAuto(origin: CpRenderedOrigin, desired: CpDesiredAutoAction) async throws -> CpAutoResult {
        let claim = try store.claimAuto(origin: origin, desired: desired, now: now())
        guard case .claimed(let owner) = claim else {
            return CpAutoResult(snapshot: try await act(origin: origin, claim: claim), activatedMode: nil)
        }
        let accepted = try await execute(owner)
        if accepted { _ = try await refresh(runAuto: false) }
        let current = try store.snapshot(now: now())
        let scope = current.context
        let activated = accepted && current.run.armed &&
            scope.accountGeneration == owner.context.accountGeneration &&
            scope.selectionRevision == owner.context.selectionRevision && scope.runID == owner.context.runID
        return CpAutoResult(snapshot: try current.displaySnapshot(now: now()), activatedMode: activated ? scope : nil)
    }
    public func signIn(owner: CpSignInOwner, token: String) async throws -> CpStoreSnapshot {
        guard try store.stageSignInCandidate(owner: owner, token: token, now: now()) else { throw CpFeedback.detailsChanged }
        let profile = try await http.send(authority: .signIn(owner), purpose: .profile, now: now)
        let identity = try cpOwnedProfile(profile.body)
        guard try store.commitCandidateProfile(admission: profile.admission, userID: identity.userId,
                email: identity.email, now: now()) else { throw CpFeedback.detailsChanged }
        _ = try await http.send(authority: .signIn(owner), purpose: .renew, now: now)
        guard let accepted = try store.finishSignIn(owner: owner, now: now()) else { throw CpFeedback.detailsChanged }
        return accepted
    }
    public func discover(owner: CpDiscoveryOwner, bounds: CpBounds) async throws -> [CpStation] {
        let response = try await http.send(authority: .discovery(owner), purpose: .stations(bounds), now: now)
        guard try store.requestCredential(authority: .discovery(owner), purpose: .stations(bounds), now: now()) != nil else {
            throw CpFeedback.detailsChanged
        }
        return try cpOwnedStations(response.body)
    }

    private func act(origin: CpRenderedOrigin, claim: CpClaimResult) async throws -> CpSnapshot {
        switch claim {
        case .modeChanged(let snapshot): return try snapshot.displaySnapshot(now: now())
        case .rejected(let feedback):
            try store.recordFeedback(origin: origin, feedback: feedback, now: now())
            return try store.snapshot(now: now()).displaySnapshot(now: now())
        case .claimed(let operation):
            let success = try await execute(operation)
            if success { return try await refresh(runAuto: false) }
            return try store.snapshot(now: now()).displaySnapshot(now: now())
        }
    }

    @discardableResult
    private func execute(_ owner: CpOperationOwner) async throws -> Bool {
        var mutationReplied = false
        do {
            let observation = try await fetch(authority: .operation(owner), location: nil)
            guard try store.validatePreflight(owner: owner, observation: observation, now: now()),
                  let operation = try store.snapshot(now: now()).operation, operation.owner == owner else { return false }
            if operation.action == .resume {
                return try store.commitOutcome(owner: owner, outcome: .success, now: now()) != nil
            }
            let response = try await http.send(authority: .operation(owner), purpose: .mutation(operation.action), now: now)
            mutationReplied = true
            if [.accept, .snooze, .unsnooze].contains(operation.action) {
                guard let object = try JSONSerialization.jsonObject(with: Data(response.body.utf8)) as? [String: Any],
                      object["error"] == nil, object["error_message"] == nil,
                      let result = object["result"] as? NSNumber, CFGetTypeID(result) == CFBooleanGetTypeID() else {
                    throw CpObservationError.malformed
                }
                var refused = !result.boolValue
                if let rawResponse = object["response"] {
                    guard let details = rawResponse as? [String: Any],
                          details["error"] == nil, details["error_message"] == nil else {
                        throw CpObservationError.malformed
                    }
                    if let rawSuccess = details["success"] {
                        guard let success = rawSuccess as? NSNumber,
                              CFGetTypeID(success) == CFBooleanGetTypeID() else {
                            throw CpObservationError.malformed
                        }
                        refused = refused || !success.boolValue
                    }
                }
                if refused {
                    _ = try store.commitOutcome(owner: owner, outcome: .refused(CP_REFUSED), now: now(), synchronousAlert: onAlert)
                    return false
                }
            }
            if operation.action == .stop {
                guard let object = try JSONSerialization.jsonObject(with: Data(response.body.utf8)) as? [String: Any],
                      object["error"] == nil, object["error_message"] == nil,
                      let id = object["ackId"] as? NSNumber, CFGetTypeID(id) != CFBooleanGetTypeID(),
                      let ack = Int64(id.stringValue), ack > 0,
                      try store.recordAcknowledgement(owner: owner, admission: response.admission, id: ack, now: now()) else {
                    throw CpObservationError.malformed
                }
                var confirmed = false
                for _ in 0..<75 {
                    do {
                        _ = try await http.send(authority: .operation(owner), purpose: .acknowledgement(ack), now: now)
                        confirmed = true; break
                    } catch let error as HaError where error.code != 401 && error.code != 403 {
                        try await Task.sleep(nanoseconds: 750_000_000)
                    }
                }
                guard confirmed else { throw URLError(.timedOut) }
            }
            return try store.commitOutcome(owner: owner, outcome: .success, now: now(), synchronousAlert: onAlert) != nil
        } catch {
            let operation = try store.snapshot(now: now()).operation
            if operation?.owner == owner, operation?.stage == .admitted {
                if !mutationReplied, let status = error as? HaError, status.code == 403 {
                    _ = try store.commitOutcome(owner: owner, outcome: .refused(status.message), now: now(), synchronousAlert: onAlert)
                } else {
                    _ = try store.commitOutcome(owner: owner, outcome: .uncertain, now: now(), synchronousAlert: onAlert)
                }
            } else if operation?.owner == owner, operation?.stage != .uncertain {
                _ = try store.commitOutcome(owner: owner, outcome: .cancelledBeforeAdmission, now: now())
            }
            return false
        }
    }

    private func fetch(authority: CpRequestAuthority, location: CpLocation?) async throws -> CpObservation {
        let status = try await http.send(authority: authority, purpose: .status, now: now).body
        let initial = try cpOwnedObservation(statusJson: status)
        let inline: String?
        if initial.identity.queued {
            inline = try? await http.send(authority: authority, purpose: .inline, now: now).body
        } else { inline = nil }
        var allowance: String?
        if let token = initial.identity.token, ["ACCEPT_PENDING", "PENDING_PLUG_IN", "DIB_PENDING_PLUG_IN"].contains(initial.identity.phase) {
            allowance = try? await http.send(authority: authority, purpose: .allowance(token), now: now).body
        }
        var charging: String?
        if let id = initial.identity.sessionID {
            charging = try? await http.send(authority: authority, purpose: .charging(id), now: now).body
        }
        var available: CpNow?
        var floors: [CpFloor] = []
        if let location, let raw = try? await http.send(authority: authority, purpose: .stations(location.bounds), now: now).body {
            let stations = (try? cpOwnedStations(raw)) ?? []
            if stations.contains(where: { location.deviceIds.contains($0.deviceId) }) { available = cpLocationNow(location, stations) }
            floors = cpFloorsFrom(location, stations)
        }
        return try cpOwnedObservation(statusJson: status, inlineJson: inline,
            details: CpDetailEvidence(allowanceToken: initial.identity.token, allowanceJson: allowance,
                chargingSessionID: initial.identity.sessionID, chargingJson: charging), availability: available, floors: floors)
    }
}
