import Foundation

/// Fetches the live ChargePoint snapshot from the user's web session: the waitlist / offer / held /
/// charging state (userStatus, refined by inlineStatus for the place and chargingDetail for the live
/// session). Plug counts and joining from the widget need a chosen location (see
/// docs/CHARGEPOINT-IOS.md); until one is set, an idle signed-in user shows "Set up".
public func fetchCpSnapshot(_ session: CpSession,
                            onToken: @escaping @Sendable (String) -> Void = { _ in },
                            autoOn: Bool = false, now: Date = Date()) async -> CpSnapshot {
    let checked = cpClockString(now)
    guard session.isSignedIn else {
        return cpSnapshot(cpSignedOutState(session, autoOn: autoOn), email: session.email, checkedAt: checked)
    }
    let client = CpClient(token: session.token, userId: session.userId, onToken: onToken)
    do {
        let statusJson = try await client.userStatus()
        var waitlist = cpWaitlistFrom(statusJson, nil)
        if case .inLine = waitlist {
            waitlist = cpWaitlistFrom(statusJson, try? await client.inlineStatus())
        }
        var charging: CpCharging?
        if let sessionId = cpSessionId(statusJson) {
            charging = cpChargingFrom(try? await client.chargingDetail(sessionId: sessionId))
        }
        let state = CpState(signedOut: false,
                            account: cpAccount(hasSession: true, expired: false, joinExpired: session.joinExpired),
                            location: nil, now: nil, waitlist: waitlist, charging: charging, autoOn: autoOn)
        return cpSnapshot(state, email: session.email, checkedAt: checked)
    } catch let e as HaError where e.code == 401 {
        var expired = session; expired.expired = true
        return cpSnapshot(cpSignedOutState(expired, autoOn: autoOn), email: session.email, checkedAt: checked)
    } catch {
        // Keep showing signed-in (transient error); next refresh retries.
        let state = CpState(signedOut: false, account: cpAccount(hasSession: true, expired: false),
                            location: nil, now: nil, waitlist: .notQueued, charging: nil, autoOn: autoOn)
        return cpSnapshot(state, email: session.email, checkedAt: checked)
    }
}

private func cpSignedOutState(_ session: CpSession, autoOn: Bool) -> CpState {
    CpState(signedOut: true, account: cpAccount(hasSession: false, expired: session.expired),
            location: nil, now: nil, waitlist: .notQueued, charging: nil, autoOn: autoOn)
}

private func cpClockString(_ date: Date) -> String {
    let f = DateFormatter(); f.dateFormat = "h:mm a"; return f.string(from: date)
}
