import Foundation
import HearthKit

/// Live providers use only cache owned by the current account and selected sources.
enum CollectionLiveSnapshots {
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

    /// The lights as they are now. A failed read keeps the last successful reading's lights as
    /// last known (Unavailable), from the same account-owned cache the other collections use.
    static func lights(now: Date = .now) async -> LightsSnapshot {
        guard let context = HaConfigStore.context(), let store = HaConfigStore.store else {
            return LightsSnapshot(summary: lightsSummary([], now: now), checkedAt: "", state: .failed,
                                  error: "Can't read settings · Reopen Hearth")
        }
        guard let config = context.config, config.carReady else {
            return mapLightsSnapshot(context.config, reply: .success("[]"), now: now)
        }
        var owner: HaCollectionReadOwner?
        do {
            guard let readID = try store.beginCollectionRead(lightsCacheKind, expectedScope: context.scope,
                expectedRevision: context.collectionRevision) else { return storedLights(now: now) }
            owner = HaCollectionReadOwner(kind: lightsCacheKind, scope: context.scope,
                                          revision: context.collectionRevision, readID: readID)
            let reply: Result<String, HaError>
            do {
                let raw = try await HaClient(config).template(LIGHTS_TEMPLATE)
                try validateLightsReading(raw)
                reply = .success(raw)
            } catch { reply = .failure(HaError(friendlyError(error))) }
            if Task.isCancelled { return storedLights(now: now) }
            guard let result = try store.mergeCollection(lightsCacheKind, reply: reply, expectedScope: context.scope,
                expectedRevision: context.collectionRevision, readID: readID, now: now) else { return storedLights(now: now) }
            return storedLights(result, now: now)
        } catch {
            guard !Task.isCancelled, let owner,
                  let failed = try? store.failCollectionRead(owner, error: "Can't save readings · Refresh to retry", now: now)
            else { return storedLights(now: now) }
            return storedLights(failed, now: now)
        }
    }

    private static let lightsCacheKind = "lights"

    private static func storedLights(_ context: HaStoreSnapshot? = HaConfigStore.context(), now: Date) -> LightsSnapshot {
        let cache = context?.collectionCaches[lightsCacheKind]
        let previous = cache.flatMap { value -> LightsSnapshot? in
            guard let raw = value.payload, let at = value.observedAt else { return nil }
            return mapLightsSnapshot(context?.config, reply: .success(raw), now: at)
        }
        if let error = cache?.error {
            return mapLightsSnapshot(context?.config, reply: .failure(HaError(error)), previous: previous, now: now)
        }
        return previous ?? mapLightsSnapshot(context?.config, reply: .failure(HaError("No reading · Refresh to check")), now: now)
    }

    private static func clock(_ date: Date?) -> String {
        guard let date else { return "" }
        return HearthTimeFormatter.shortTime(date)
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
}
