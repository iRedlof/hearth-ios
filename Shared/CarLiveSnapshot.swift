import Foundation
import HearthKit

/// One raw-reading cache for the app and widget. Request scope prevents a late reply from the
/// previous HA account from restoring readings after sign-out or a server change.
enum CarLiveSnapshot {
    private static let key = "carReadings"
    private static var defaults: UserDefaults { UserDefaults(suiteName: HaConfigStore.appGroup) ?? .standard }
    private struct Stored: Codable {
        let scope: String
        let readings: CarReadingsCache
    }
    static func clear() { defaults.removeObject(forKey: key) }
    private static func load(scope: String) -> CarReadingsCache? {
        guard let data = defaults.data(forKey: key),
              let stored = try? JSONDecoder().decode(Stored.self, from: data),
              stored.scope == scope else { return nil }
        return stored.readings
    }
    static func fetch(now: Date = .now) async -> CarSnapshot {
        let scope = HaConfigStore.requestScope()
        let config = HaConfigStore.load()
        var result = await fetchCarReadings(config, previous: load(scope: scope), now: now)
        guard HaConfigStore.isCurrent(scope, config: config) else {
            let current = HaConfigStore.load()
            let cached = load(scope: HaConfigStore.requestScope())
            return CarFetchResult(cache: cached,
                error: current?.carReady == true ? "Configuration changed · Refresh to check" : nil,
                setup: current?.carReady != true).snapshot(now: now)
        }
        if let newer = load(scope: scope), newer.checkedAt > now {
            return CarFetchResult(cache: newer).snapshot(now: now)
        }
        if result.error == nil, let cache = result.cache,
           let reconciled = try? carReadingsAfterReply(cache.current,
                previous: load(scope: scope), checkedAt: cache.checkedAt) {
            result = CarFetchResult(cache: reconciled)
        }
        if result.error == nil, let cache = result.cache,
           let data = try? JSONEncoder().encode(Stored(scope: scope, readings: cache)) {
            // A concurrently completed older read must not overwrite a newer successful one.
            if load(scope: scope).map({ $0.checkedAt <= cache.checkedAt }) ?? true {
                defaults.set(data, forKey: key)
            }
        }
        if let latest = load(scope: scope),
           latest.checkedAt > (result.cache?.checkedAt ?? .distantPast) {
            return CarFetchResult(cache: latest, error: result.error).snapshot(now: now)
        }
        return result.snapshot(now: now)
    }
}
