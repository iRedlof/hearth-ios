import Foundation
import HearthKit

/// Live providers use only cache owned by the current account and selected sources.
enum CollectionLiveSnapshots {
    private struct DoorCache: Codable {
        let readings: [String: HaStateReading]
        let errors: [String: String]
    }

    static func batteries(now: Date = .now) async -> BatterySnapshot {
        guard let context = HaConfigStore.context(), let store = HaConfigStore.store else {
            return BatterySnapshot(summary: batterySummary([]), checkedAt: "", state: .failed, error: "Can't read settings · Reopen Hearth")
        }
        guard let config = context.config, config.carReady else { return mapBatterySnapshot(context.config, reply: .success("[]"), now: now) }
        var owner: HaCollectionReadOwner?
        do {
            guard let readID = try store.beginCollectionRead("batteries", expectedScope: context.scope,
                expectedRevision: context.collectionRevision) else { return storedBatteries(now: now) }
            owner = HaCollectionReadOwner(kind: "batteries", scope: context.scope, revision: context.collectionRevision, readID: readID)
            let reply: Result<String, HaError>
            do {
                let raw = try await HaClient(config).template(BATTERY_TEMPLATE)
                _ = try parseBatteryCollection(raw)
                reply = .success(raw)
            } catch { reply = .failure(HaError(friendlyError(error))) }
            if Task.isCancelled { return storedBatteries(now: now) }
            guard let result = try store.mergeCollection("batteries", reply: reply, expectedScope: context.scope,
                expectedRevision: context.collectionRevision, readID: readID, now: now) else { return storedBatteries(now: now) }
            return storedBatteries(result, now: now)
        } catch {
            guard !Task.isCancelled, let owner,
                  let failed = try? store.failCollectionRead(owner, error: "Can't save readings · Refresh to retry", now: now)
            else { return storedBatteries(now: now) }
            return storedBatteries(failed, now: now)
        }
    }

    static func activity(now: Date = .now) async -> ActivitySnapshot {
        guard let context = HaConfigStore.context(), let store = HaConfigStore.store else {
            return ActivitySnapshot(items: [], checkedAt: "", state: .failed, error: "Can't read settings · Reopen Hearth")
        }
        guard let config = context.config, config.carReady else {
            return mapActivitySnapshot(config: context.config, reply: .success("[]"), names: [:], now: now)
        }
        var owner: HaCollectionReadOwner?
        do {
            guard let readID = try store.beginCollectionRead("activity", expectedScope: context.scope,
                expectedRevision: context.collectionRevision) else { return storedActivity(now: now) }
            owner = HaCollectionReadOwner(kind: "activity", scope: context.scope, revision: context.collectionRevision, readID: readID)
            let previous = storedActivity(context, now: now)
            let live = await fetchActivitySnapshot(config, now: now, previous: previous)
            if Task.isCancelled { return storedActivity(now: now) }
            let reply: Result<String, HaError>
            if live.state == .failed { reply = .failure(HaError(live.error ?? "History unavailable")) }
            else {
                let data = try JSONEncoder().encode(live.items)
                guard let json = String(data: data, encoding: .utf8) else { throw HaError("Couldn't save history") }
                reply = .success(json)
            }
            guard let result = try store.mergeCollection("activity", reply: reply, expectedScope: context.scope,
                expectedRevision: context.collectionRevision, readID: readID, now: now) else { return storedActivity(now: now) }
            return storedActivity(result, now: now)
        } catch {
            guard !Task.isCancelled, let owner,
                  let failed = try? store.failCollectionRead(owner, error: "Can't save history · Refresh to retry", now: now)
            else { return storedActivity(now: now) }
            return storedActivity(failed, now: now)
        }
    }

    static func doors(now: Date = .now) async -> DoorsSnapshot {
        guard var context = try? HaConfigStore.doorsContext(now: now), let store = HaConfigStore.store else {
            return DoorsSnapshot(summary: doorsSummary([], now: now), checkedAt: "", state: .failed,
                error: "Can't read settings · Reopen Hearth")
        }
        guard var config = context.config, config.carReady else {
            return mapDoorsSnapshot(config: context.config, readings: [:], errors: [:], now: now)
        }
        if context.doorOperation?.pending == true { return storedDoors(context, now: now) }
        var owner: HaCollectionReadOwner?
        do {
            guard let readID = try store.beginCollectionRead("doors", expectedScope: context.scope,
                expectedRevision: context.collectionRevision) else { return storedDoors(now: now) }
            owner = HaCollectionReadOwner(kind: "doors", scope: context.scope, revision: context.collectionRevision, readID: readID)
            if config.doorIds.isEmpty && !config.doorsChosen {
                let found = try defaultDoorIDs(await HaClient(config).allStatesJson(), lockID: config.lockId)
                guard !Task.isCancelled,
                      let adopted = try store.adoptDoorDiscovery(found, expectedScope: context.scope,
                        expectedRevision: context.collectionRevision, readID: readID),
                      let adoptedConfig = adopted.config else { return storedDoors(now: now) }
                context = adopted
                config = adoptedConfig
                owner = HaCollectionReadOwner(kind: "doors", scope: context.scope, revision: context.collectionRevision, readID: readID)
            }
            let ids = doorsSelectedIDs(config)
            let previous = decodeDoors(context.collectionCaches["doors"]?.payload)?.readings ?? [:]
            let capturedConfig = config
            let result = await fetchHaStateReadings(capturedConfig, ids: ids, previous: previous, now: now) { id in
                let raw = try await HaClient(capturedConfig).stateJson(id)
                guard let door = doorFromState(raw), door.id == id else { throw HaError("Unexpected entity reading") }
                return raw
            }
            if Task.isCancelled { return storedDoors(now: now) }
            let cache = DoorCache(readings: result.readings, errors: result.errors)
            let json = String(data: try JSONEncoder().encode(cache), encoding: .utf8) ?? ""
            guard let saved = try store.mergeCollection("doors", reply: .success(json), expectedScope: context.scope,
                expectedRevision: context.collectionRevision, readID: readID, now: now) else { return storedDoors(now: now) }
            return storedDoors(saved, now: now)
        } catch {
            guard !Task.isCancelled, let owner,
                  let failed = try? store.failCollectionRead(owner, error: friendlyError(error), now: now)
            else { return storedDoors(now: now) }
            return storedDoors(failed, now: now)
        }
    }

    private static func clock(_ date: Date?) -> String {
        guard let date else { return "" }
        let format = DateFormatter(); format.dateFormat = "h:mm a"; return format.string(from: date)
    }
    private static func storedBatteries(_ context: HaStoreSnapshot? = HaConfigStore.context(), now: Date) -> BatterySnapshot {
        let cache = context?.collectionCaches["batteries"]
        let previous = cache.flatMap { value -> BatterySnapshot? in
            guard let raw = value.payload, let at = value.observedAt else { return nil }
            return mapBatterySnapshot(context?.config, reply: .success(raw), now: at)
        }
        if let error = cache?.error {
            return mapBatterySnapshot(context?.config, reply: .failure(HaError(error)), previous: previous, now: now)
        }
        return previous ?? mapBatterySnapshot(context?.config, reply: .failure(HaError("No reading · Refresh to check")), now: now)
    }
    private static func storedActivity(_ context: HaStoreSnapshot? = HaConfigStore.context(), now: Date) -> ActivitySnapshot {
        guard context?.config?.carReady == true else {
            return mapActivitySnapshot(config: context?.config, reply: .success("[]"), names: [:], now: now)
        }
        let cache = context?.collectionCaches["activity"]
        let items = cache?.payload.flatMap { $0.data(using: .utf8) }.flatMap { try? JSONDecoder().decode([ActivityItem].self, from: $0) }
        let corrupt = cache?.payload != nil && items == nil
        let error = cache?.error ?? (corrupt ? "Saved history unavailable · Refresh to check" : nil)
        let recent = activityInWindow(items ?? [], now: now)
        return ActivitySnapshot(items: recent, checkedAt: clock(cache?.observedAt),
            state: error != nil ? .failed : cache == nil ? .loading : recent.isEmpty ? .empty : .ready,
            error: error, observedAt: cache?.observedAt, windowEnd: cache?.observedAt)
    }
    private static func decodeDoors(_ json: String?) -> DoorCache? {
        json?.data(using: .utf8).flatMap { try? JSONDecoder().decode(DoorCache.self, from: $0) }
    }
    private static func storedDoors(_ context: HaStoreSnapshot? = HaConfigStore.context(), now: Date) -> DoorsSnapshot {
        let stored = context?.collectionCaches["doors"]
        let cache = decodeDoors(stored?.payload)
        var readings = cache?.readings ?? [:]
        var errors = cache?.errors ?? [:]
        let corrupt = stored?.payload != nil && cache == nil
        let collectionError = stored?.error ?? (corrupt ? "Saved doors unavailable · Refresh to check" : nil)
        if let config = context?.config, let message = collectionError {
            for id in doorsSelectedIDs(config) { errors[id] = message }
        }
        var operation = context?.doorOperation
        if let operation, let fresh = context?.readings[operation.entityID],
           fresh.checkedAt >= operation.startedAt,
           errors[fresh.entityID] == nil || fresh.checkedAt >= (stored?.attemptedAt ?? .distantPast),
           readings[fresh.entityID].map({ $0.checkedAt <= fresh.checkedAt }) ?? true {
            readings[fresh.entityID] = fresh
            errors.removeValue(forKey: fresh.entityID)
        }
        if let finished = operation, !finished.pending, let ended = finished.endedAt,
           let read = readings[finished.entityID], read.checkedAt > ended, errors[finished.entityID] == nil {
            operation = nil
        }
        if let operation, let error = operation.error { errors[operation.entityID] = error }
        let mapped = mapDoorsSnapshot(config: context?.config, readings: readings, errors: errors, now: now,
            collectionError: collectionError)
        return DoorsSnapshot(summary: mapped.summary, checkedAt: mapped.checkedAt, state: mapped.state,
            error: mapped.error, observedAt: mapped.observedAt, doors: mapped.doors,
            actionScope: context?.scope, actionRevision: context?.doorActionRevision, operation: operation)
    }
}
