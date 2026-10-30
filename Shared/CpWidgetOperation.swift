import Foundation
import WidgetKit
import HearthKit

/// Shared AppIntent integration: one pending operation, visible failures, and mode-preserving completion.
@MainActor enum CpWidgetOperation {
    static func perform(_ name: String, snoozeSeconds: Int = CP_AUTO_SNOOZE_SECONDS) async {
        guard let parsed = cpCommandNamed(name) else { return }
        let command: CpCommand = name == "snooze" ? .snooze(snoozeSeconds) : parsed
        await execute(name) { client, _, location, canAct in
            try await cpPerformManual(command, client: client, location: location,
                                      udid: CpSessionStore.udid(), canAct: canAct)
            return nil
        }
    }

    static func enableAuto() async {
        await execute("auto") { client, run, location, canAct in
            guard let location else { throw HaError("Choose a location first") }
            return try await cpEnableAuto(run, client: client, location: location,
                                          now: Int64(Date().timeIntervalSince1970 * 1000), canAct: canAct)
        }
    }

    private static func execute(_ name: String,
        work: (CpClient, CpRun, CpLocation?, @Sendable () async -> Bool) async throws -> CpRun?) async {
        if let operation = CpSessionStore.loadOperation(), operation.error == nil,
           Date().timeIntervalSince(operation.startedAt) < 120 { return }
        let session = CpSessionStore.load()
        guard session.isSignedIn else { return }
        let scope = CpSessionStore.requestScope()
        let location = CpSessionStore.loadLocation()
        let before = CpSessionStore.loadRun()
        let operation = CpOperation(command: name)
        CpSessionStore.saveOperation(operation)
        let revision = CpSessionStore.activityRevision()
        let canAct: @Sendable () async -> Bool = {
            CpSessionStore.isCurrent(scope) && CpSessionStore.loadOperation()?.id == operation.id &&
                (name != "auto" || CpSessionStore.activityRevision() == revision)
        }
        reload()
        let client = CpClient(token: session.token, userId: session.userId,
                              onToken: { CpSessionStore.saveToken($0, scope: scope) })
        do {
            let result = try await work(client, before, location, canAct)
            guard CpSessionStore.isCurrent(scope), CpSessionStore.loadOperation()?.id == operation.id else {
                reload(); return
            }
            let current = CpSessionStore.loadRun()
            // A command started in an older run cannot overwrite a replacement run.
            if current.startedAt == before.startedAt {
                if let result {
                    if CpSessionStore.activityRevision() == revision { CpSessionStore.saveRun(result) }
                }
                else if let command = cpCommandNamed(name) {
                    CpSessionStore.saveRun(cpAfterManual(current, command, true))
                }
            }
            CpSessionStore.saveOperation(nil)
        } catch {
            guard CpSessionStore.isCurrent(scope), CpSessionStore.loadOperation()?.id == operation.id else {
                reload(); return
            }
            if error is CancellationError { CpSessionStore.saveOperation(nil) }
            else {
                var failed = operation; failed.error = friendlyError(error)
                CpSessionStore.saveOperation(failed)
            }
            if let error = error as? HaError, error.code == 401 {
                CpSessionStore.markExpired(scope: scope)
            }
        }
        reload()
    }

    static func reload() {
        WidgetCenter.shared.reloadTimelines(ofKind: "com.rohit.hearth.chargepoint")
        RefreshSignal.shared.bump()
    }
}
