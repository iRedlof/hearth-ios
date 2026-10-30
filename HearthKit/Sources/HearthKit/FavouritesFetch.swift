import Foundation

public struct FavSnapshot: Sendable, Equatable {
    public let items: [Fav]; public let checkedAt: String
    public let state: TileSnapshotState; public let error: String?
    public init(items: [Fav], checkedAt: String, state: TileSnapshotState = .ready, error: String? = nil) {
        self.items = items; self.checkedAt = checkedAt; self.state = state; self.error = error
    }
    public static let loading = FavSnapshot(items: [], checkedAt: "", state: .loading)

    public static let sample = FavSnapshot(items: [
        Fav(id: "switch.coffee", name: "Coffee Maker", on: true),
        Fav(id: "light.lamp", name: "Corner Lamp", on: false),
        Fav(id: "fan.bedroom", name: "Bedroom Fan", on: true),
        Fav(id: "input_boolean.guest", name: "Guest Mode", on: false),
        Fav(id: "script.movie", name: "Movie Time", on: false),
        Fav(id: "switch.patio", name: "Patio Lights", on: true),
    ], checkedAt: "9:41 AM")
}

/// The configured favourites (≤12, ordered) with their names + on-state. Each is read from HA.
public func fetchFavouritesSnapshot(_ config: HaConfig?, now: Date = Date(),
    read: (@Sendable (String) async throws -> String)? = nil) async -> FavSnapshot {
    guard let config, config.carReady else { return mapFavouritesSnapshot(config, replies: [:], now: now) }
    let client = HaClient(config)
    var replies: [String: Result<String, HaError>] = [:]
    for id in config.favouriteIds.prefix(12) {
        do {
            let json: String
            if let read { json = try await read(id) } else { json = try await client.stateJson(id) }
            replies[id] = .success(json)
        } catch { replies[id] = .failure(HaError(tileReadError(error))) }
    }
    return mapFavouritesSnapshot(config, replies: replies, now: now)
}

public func mapFavouritesSnapshot(_ config: HaConfig?, replies: [String: Result<String, HaError>],
    now: Date = Date()) -> FavSnapshot {
    let checked = widgetClock(now)
    guard let config, config.carReady else {
        return FavSnapshot(items: [], checkedAt: "", state: .setup)
    }
    let ids = Array(config.favouriteIds.prefix(12))
    guard !ids.isEmpty else { return FavSnapshot(items: [], checkedAt: "", state: .choose) }
    var items: [Fav] = []
    var errors: [String] = []
    var succeeded = false
    for id in ids {
        do {
            let json = try (replies[id] ?? .failure(HaError("No entity reading"))).get()
            items.append(try favouriteFromState(json, id: id))
            succeeded = true
        } catch {
            items.append(Fav(id: id, name: scriptShortName(id), on: false, available: false))
            errors.append(tileReadError(error))
        }
    }
    return FavSnapshot(items: items, checkedAt: succeeded ? checked : "",
                       state: succeeded ? .ready : .failed, error: errors.first)
}

/// Preserve selected unavailable entities in place; unknown never becomes an actionable Off.
public func favouriteFromState(_ json: String, id: String) throws -> Fav {
    let object = try tileStateObject(json, id: id)
    let state = object["state"] as? String
    let domain = String(id.prefix { $0 != "." })
    let allowed = ["switch", "light", "fan", "input_boolean", "script"].contains(domain)
    return Fav(id: id, name: friendlyName(ofStateJson: json) ?? scriptShortName(id), on: state == "on",
               available: allowed && ["on", "off"].contains(state ?? ""))
}
