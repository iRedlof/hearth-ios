import Foundation

public struct FavSnapshot: Sendable, Equatable {
    public let items: [Fav]; public let checkedAt: String
    public init(items: [Fav], checkedAt: String) { self.items = items; self.checkedAt = checkedAt }

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
public func fetchFavouritesSnapshot(_ config: HaConfig, now: Date = Date()) async -> FavSnapshot {
    let checked = widgetClock(now)
    let ids = Array(config.favouriteIds.prefix(12))
    guard config.baseUrl.hasPrefix("https://"), config.hasAuth, !ids.isEmpty else { return .sample }
    let client = HaClient(config)
    var items: [Fav] = []
    for id in ids {
        guard let json = try? await client.stateJson(id) else { continue }
        let name = friendlyName(ofStateJson: json) ?? scriptShortName(id)
        items.append(Fav(id: id, name: name, on: favStateOn(json)))
    }
    return FavSnapshot(items: items, checkedAt: checked)
}

private func favStateOn(_ json: String) -> Bool {
    guard let data = json.data(using: .utf8),
          let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return false }
    return (obj["state"] as? String) == "on"
}
