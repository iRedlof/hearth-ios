import Foundation
import HearthKit

enum AlarmLiveSnapshot {
    static func fetch(now: Date = .now) async -> AlarmSnapshot {
        guard let context = try? HaConfigStore.alarmContext(now: now) else { return storageUnavailable(now: now) }
        // While one of the card's own commands is in flight, only that command's validated replies
        // update the card; an ordinary refresh waits for it (the Doors card did the same).
        if context.alarmOperation?.pending == true || garageCommandPending(context) {
            return alarmStoredSnapshot(context, now: now)
        }
        let result = await fetchAlarmReadings(context.config, previous: context.readings, now: now)
        do {
            guard let store = HaConfigStore.store,
                  let merged = try store.merge(result.readings, expectedScope: context.scope,
                    expectedAlarmRevision: context.alarmRevision, failures: result.errors, checkedAt: now),
                  context.config?.entityId == merged.config?.entityId,
                  context.config?.lockId == merged.config?.lockId,
                  context.config.flatMap(garageSelectedID) == merged.config.flatMap(garageSelectedID) else {
                return cached(now: now, error: "Configuration changed · Refresh to check")
            }
            return alarmStoredSnapshot(merged, now: now)
        } catch { return cached(now: now, error: "Can't save readings · Refresh to retry") }
    }

    static func currentFeedback(_ snapshot: AlarmSnapshot, now: Date = .now) -> AlarmSnapshot {
        guard let context = try? HaConfigStore.alarmContext(now: now) else { return storageUnavailable(now: now) }
        return alarmCurrentFeedback(snapshot, context: context, now: now)
    }
    private static func garageCommandPending(_ context: HaStoreSnapshot) -> Bool {
        guard let operation = context.doorOperation, operation.pending else { return false }
        return operation.entityID == context.config.flatMap(garageSelectedID)
    }
    private static func cached(now: Date, error: String) -> AlarmSnapshot {
        guard let context = HaConfigStore.context() else { return storageUnavailable(now: now) }
        return alarmStoredSnapshot(context, now: now, transientError: error)
    }
    private static func storageUnavailable(now: Date) -> AlarmSnapshot {
        var result = AlarmFetchResult(setup: true).snapshot(now: now)
        result.stateWord = "Can't read settings"
        result.detail = "Reopen Hearth"
        result.error = "Shared storage is unavailable. Please reopen Hearth."
        return result
    }
}
