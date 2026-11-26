import Foundation

/// Fetches the live ChargePoint snapshot from the user's web session: the waitlist / offer / held /
/// charging state (userStatus, refined by inlineStatus for the place and chargingDetail for the live
/// session). Plug counts and joining from the widget need a chosen location (see
/// docs/CHARGEPOINT-IOS.md); until one is set, an idle signed-in user shows "Set up".
public func fetchCpSnapshot(_ session: CpSession, location: CpLocation? = nil,
                            onToken: @escaping @Sendable (String) -> Void = { _ in },
                            autoOn: Bool = false, now: Date = Date(),
                            client suppliedClient: CpClient? = nil, previous: CpSnapshot? = nil,
                            onExpired: @escaping @Sendable () -> Void = {}) async -> CpSnapshot {
    let checked = cpClockString(now)
    guard session.isSignedIn else {
        return cpSnapshot(cpSignedOutState(session, location: location, autoOn: autoOn), email: session.email,
                          checkedAt: previous?.checkedAt ?? "—", now: now)
    }
    let client = suppliedClient ?? CpClient(token: session.token, userId: session.userId, onToken: onToken)
    do {
        let statusJson = try await client.userStatus()
        var waitlist = cpWaitlistFrom(statusJson, nil)
        if case .inLine = waitlist {
            waitlist = cpWaitlistFrom(statusJson, try? await client.inlineStatus())
        }
        var snoozesLeft: Int?
        if case let .inLine(_, state, _, _, _) = waitlist,
           ["ACCEPT_PENDING", "PENDING_PLUG_IN", "DIB_PENDING_PLUG_IN"].contains(state),
           let token = cpOfferToken(statusJson) {
            snoozesLeft = cpSnoozesFrom(try? await client.snoozeDetail(offerToken: token))
        }
        var charging: CpCharging?
        if let sessionId = cpSessionId(statusJson) {
            charging = cpChargingFrom(try? await client.chargingDetail(sessionId: sessionId))
                ?? CpCharging(sessionId: sessionId, powerKw: nil, energyKwh: nil, minutes: nil, canStop: false)
        }
        var cpNow: CpNow?
        var floors: [CpFloor] = []
        if let location, let stationsJson = try? await client.stations(location.bounds) {
            let stations = cpStationsFrom(stationsJson)
            if stations.contains(where: { location.deviceIds.contains($0.deviceId) }) {
                cpNow = cpLocationNow(location, stations)
            }
            floors = cpFloorsFrom(location, stations)
        }
        let state = CpState(signedOut: false,
                            account: cpAccount(hasSession: true, expired: false, joinExpired: session.joinExpired),
                            location: location, now: cpNow, waitlist: waitlist, charging: charging,
                            autoOn: autoOn, floors: floors, snoozesLeft: snoozesLeft)
        return cpSnapshot(state, email: session.email, checkedAt: checked, now: now)
    } catch let e as HaError where e.code == 401 {
        var expired = session; expired.expired = true
        onExpired()
        return cpSnapshot(cpSignedOutState(expired, location: location, autoOn: autoOn), email: session.email,
                          checkedAt: previous?.checkedAt ?? "—", now: now)
    } catch {
        // A failed check retains the selected building and the last successful reading.
        let state = CpState(signedOut: false, account: cpAccount(hasSession: true, expired: false),
                            location: location, now: nil, waitlist: .notQueued, charging: nil, autoOn: autoOn)
        var snapshot = previous ?? cpSnapshot(state, email: session.email, checkedAt: "—", now: now)
        snapshot.sub = "Couldn't check · Refresh to retry"
        snapshot.stale = true
        return snapshot
    }
}

private func cpSignedOutState(_ session: CpSession, location: CpLocation?, autoOn: Bool) -> CpState {
    CpState(signedOut: true, account: cpAccount(hasSession: false, expired: session.expired),
            location: location, now: nil, waitlist: .notQueued, charging: nil, autoOn: autoOn)
}

func cpClockString(_ date: Date) -> String {
    let f = DateFormatter(); f.dateFormat = "h:mm a"; return f.string(from: date)
}

/// `response.remainingSnoozeCount` from a `get_notification_detail` body (spec R4).
public func cpSnoozesFrom(_ json: String?) -> Int? {
    guard let json, let data = json.data(using: .utf8),
          let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let response = obj["response"] as? [String: Any] else { return nil }
    if let i = response["remainingSnoozeCount"] as? Int { return i }
    if let i = response["remainingSnoozeCount"] as? Int64 { return Int(i) }
    return nil
}

/// The auto-waitlist RUNTIME: run the (tested) `cpAutoDecide` against the live status and act on its
/// decision — auto-accept the offer, auto-snooze once, raise a drive-now alert, or disarm when
/// charging. Returns the updated `CpRun` (persist it) and any alert to surface. iOS can only call
/// this when the widget/app actually refreshes — there is no guaranteed background cadence or exact
/// pre-deadline wake, so unattended accept/snooze is best-effort (see docs/CHARGEPOINT-IOS.md). The
/// decision itself is exact; only *when iOS lets it run* differs from Android.
public func cpAdvanceAuto(_ run: CpRun, client: CpClient, statusJson: String,
                          now: Int64,
                          canAct: @escaping @Sendable () async -> Bool = { true },
                          decisionNow: @Sendable () -> Int64? = { nil }) async -> (run: CpRun, alert: CpAlert?) {
    guard run.armed, await canAct() else { return (run, nil) }
    var run = run
    let waitlist = cpWaitlistFrom(statusJson, nil)
    let charging = cpSessionId(statusJson) != nil
    var state = ""
    var untilMs: Int64?
    if case let .inLine(_, s, _, offer, _) = waitlist {
        state = s
        untilMs = offer.flatMap { $0.untilMs > 0 ? $0.untilMs : nil }
    }
    // A fresh offer episode re-arms the one-shot "your turn" notification (Android resets per offer).
    if state != "ACCEPT_PENDING" { run.offerPushed = false }
    var snoozesLeft: Int?
    if CP_HELD.contains(state), let token = cpOfferToken(statusJson) {
        snoozesLeft = cpSnoozesFrom(try? await client.snoozeDetail(offerToken: token))
    }
    // Status/detail reads suspend. Recheck the user's current mode before any cloud command.
    guard await canAct() else { return (run, nil) }
    let step = cpAutoDecide(run, state: state, untilMs: untilMs, snoozesLeft: snoozesLeft,
                            charging: charging, now: decisionNow() ?? now)
    switch step {
    case .accept:
        do { try await client.accept(); return (cpAfterAct(run, step, true), .accepted) }
        catch { return (cpRecordAutoFailure(run, state, untilMs, friendlyError(error)), .failed) }
    case .snooze:
        do { try await client.snooze(seconds: CP_AUTO_SNOOZE_SECONDS); return (cpAfterAct(run, step, true), .snoozed) }
        catch { return (cpRecordAutoFailure(run, state, untilMs, friendlyError(error)), .failed) }
    case .alert(let kind, let updated):
        return (updated, kind)
    case .done:
        run.armed = false; return (run, .done)
    case .wakeAt:
        // Android posts the offer once, when it first schedules the pre-deadline accept.
        if state == "ACCEPT_PENDING" && !run.offerPushed {
            run.offerPushed = true
            return (run, run.snoozeUsed ? .secondOffer : .offer)
        }
        return (run, nil)
    case .idle:
        return (run, nil)
    }
}
