import Foundation
import HearthKit

/// App and WidgetKit use the same cache, freshness and command feedback.
enum CpLiveSnapshot {
    static func fetch(now suppliedNow: Date? = nil, advanceAuto: Bool = false) async -> CpSnapshot {
        let now = suppliedNow ?? Date()
        let scope = CpSessionStore.requestScope()
        let session = CpSessionStore.load()
        let operation = CpSessionStore.loadOperation()
        if let previous = CpSessionStore.loadSnapshot() {
            let pending = applyingCurrentMode(cpApplyingOperation(previous, operation))
            if pending.working { return pending }
        }
        let before = CpSessionStore.loadRun()
        let revision = CpSessionStore.activityRevision()
        if advanceAuto && before.armed && session.isSignedIn && !session.joinExpired && operation == nil {
            let client = CpClient(token: session.token, userId: session.userId,
                                  onToken: { CpSessionStore.saveToken($0, scope: scope) })
            let canAct: @Sendable () async -> Bool = {
                CpSessionStore.isCurrent(scope) && CpSessionStore.activityRevision() == revision &&
                    CpSessionStore.loadRun().armed && CpSessionStore.loadOperation() == nil
            }
            if let status = try? await client.userStatus(), await canAct() {
                let result = await cpAdvanceAuto(before, client: client, statusJson: status,
                    now: Int64(now.timeIntervalSince1970 * 1000), canAct: canAct,
                    decisionNow: { Int64((suppliedNow ?? Date()).timeIntervalSince1970 * 1000) })
                if CpSessionStore.isCurrent(scope) {
                    let current = CpSessionStore.loadRun()
                    let uninterrupted = await canAct()
                    let merged = cpMergeRunUpdate(before, current, result.run)
                    if merged != current { CpSessionStore.saveRun(merged) }
                    if uninterrupted, let alert = result.alert,
                       cpAlertAllowed(alert, prefs: CpSessionStore.loadAlertPrefs()) {
                        let subjects = cpAlertSubjects(status)
                        let content = cpAlertContent(alert, who: subjects.who, by: subjects.by)
                        CpNotify.post(title: content.title, body: content.body, id: content.id)
                    }
                }
            }
        }
        let fetchScope = CpSessionStore.requestScope()
        let fetchRevision = CpSessionStore.activityRevision()
        let currentSession = CpSessionStore.load()
        let snapshot = await fetchCpSnapshot(currentSession, location: CpSessionStore.loadLocation(),
            onToken: { CpSessionStore.saveToken($0, scope: fetchScope) },
            autoOn: CpSessionStore.loadRun().armed, now: now, previous: CpSessionStore.loadSnapshot(),
            onExpired: { CpSessionStore.markExpired(scope: fetchScope) })
        guard CpSessionStore.isCurrent(fetchScope), CpSessionStore.activityRevision() == fetchRevision else {
            return currentConfiguration(now: now)
        }
        if !snapshot.stale { CpSessionStore.saveSnapshot(snapshot) }
        return applyingCurrentMode(cpApplyingOperation(snapshot, CpSessionStore.loadOperation(), now: now))
    }

    private static func applyingCurrentMode(_ snapshot: CpSnapshot) -> CpSnapshot {
        var value = snapshot
        if [.join, .resume, .stop].contains(value.autoControl) {
            value.autoOn = CpSessionStore.loadRun().armed
            value.autoControl = value.autoOn ? .stop : (value.actionLabel == "Join" ? .join : .resume)
        }
        return value
    }

    private static func currentConfiguration(now: Date) -> CpSnapshot {
        if let cached = CpSessionStore.loadSnapshot() {
            return applyingCurrentMode(cpApplyingOperation(cached, CpSessionStore.loadOperation(), now: now))
        }
        let session = CpSessionStore.load()
        let state = CpState(signedOut: !session.isSignedIn,
            account: cpAccount(hasSession: session.isSignedIn, expired: session.expired, joinExpired: session.joinExpired),
            location: CpSessionStore.loadLocation(), now: nil, waitlist: .notQueued, charging: nil,
            autoOn: CpSessionStore.loadRun().armed)
        var snapshot = cpSnapshot(state, email: session.email, checkedAt: "—", now: now)
        if session.isSignedIn && state.location != nil {
            snapshot.stale = true; snapshot.sub = "Configuration changed · Refresh to check"
        }
        return cpApplyingOperation(snapshot, CpSessionStore.loadOperation(), now: now)
    }
}
