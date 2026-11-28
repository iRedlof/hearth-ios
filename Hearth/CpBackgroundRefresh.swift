import BackgroundTasks
import WidgetKit
import os
import HearthKit

/// Asks iOS to run ChargePoint in the background at the next moment auto-run has something to do.
///
/// Android wakes itself with an exact alarm (`CpAutoStep.WakeAt`). iOS has no such alarm for an
/// app; a background-refresh request with an earliest date is the nearest thing. iOS decides when
/// (and whether) to honour it, so this is a second chance beside the widget's own reload time, not
/// a guarantee.
enum CpBackgroundRefresh {
    static let identifier = "com.rohit.hearth.chargepoint.refresh"
    private static let widgetKind = "com.rohit.hearth.chargepoint"
    private static let logger = Logger(subsystem: "com.rohit.hearth", category: "CpBackgroundRefresh")

    /// Must run before the app finishes launching.
    static func register() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: identifier, using: nil) { task in
            handle(task)
        }
    }

    /// Schedules the next wake while Auto is armed; cancels the request when it is not.
    static func schedule(now: Date = .now) {
        let snapshot: CpStoreSnapshot
        do { snapshot = try CpSessionStore.repository().store.snapshot(now: now) }
        catch {
            logger.error("No stored ChargePoint state to schedule from: \(error.localizedDescription, privacy: .public)")
            return
        }
        guard snapshot.run.armed else {
            BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: identifier)
            return
        }
        let request = BGAppRefreshTaskRequest(identifier: identifier)
        request.earliestBeginDate = snapshot.nextReload(now: now)
        do { try BGTaskScheduler.shared.submit(request) }
        catch { logger.error("Background refresh not scheduled: \(error.localizedDescription, privacy: .public)") }
    }

    private static func handle(_ task: BGTask) {
        nonisolated(unsafe) let task = task
        let work = Task {
            _ = await CpLiveSnapshot.fetch(advanceAuto: true)
            WidgetCenter.shared.reloadTimelines(ofKind: widgetKind)
            schedule()
            task.setTaskCompleted(success: !Task.isCancelled)
        }
        task.expirationHandler = { work.cancel() }
    }
}
