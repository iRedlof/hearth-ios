import Foundation
import HearthKit

/// Explicit raw replies feed the same mappers as the live providers. The catalog blocks all input.
enum TileParityInputs {
    private static let now = Date(timeIntervalSince1970: 1_793_379_600)
    private static let base = HaConfig(baseUrl: "https://example.com", token: "inert", entityId: "")

    /// Entity ids spelled from the fixture names ("script.movie_time"), so an unreachable read,
    /// which only has the id to name an entity by, still shows the same names as the ready one.
    private static func fixtureIDs(domain: String, names: [String], count: Int) -> [String] {
        (0..<count).map { index in
            let slug = names[index % names.count].lowercased().replacingOccurrences(of: " ", with: "_")
            let round = index / names.count
            return "\(domain).\(slug)" + (round == 0 ? "" : "_\(round + 1)")
        }
    }

    private static func raw(_ id: String, name: String, state: String) -> String {
        let object: [String: Any] = ["entity_id": id, "state": state, "attributes": ["friendly_name": name]]
        return String(data: try! JSONSerialization.data(withJSONObject: object), encoding: .utf8)!
    }

    /// Favourites fixtures: two of four on (warm), all off (calm), twelve ("+8 more"), long names,
    /// not set up, and unreachable with every favourite kept as Unavailable.
    static let favouriteStates = ["ready", "off", "overflow", "long_names", "setup", "failed"]
    private static let favouriteNames = ["Coffee maker", "Bedroom fan", "Corner lamp", "Guest mode"]
    private static let longFavouriteName = "Upstairs primary bedroom reading lamp"
    private static let overflowFavouriteCount = 12

    static func favourites(_ state: String) -> FavSnapshot {
        precondition(favouriteStates.contains(state))
        var config = base
        let ids = fixtureIDs(domain: "switch", names: favouriteNames,
                             count: state == "overflow" ? overflowFavouriteCount : favouriteNames.count)
        config.favouriteIdsJson = String(data: try! JSONEncoder().encode(ids), encoding: .utf8)!
        let replies = Dictionary(uniqueKeysWithValues: ids.enumerated().map { index, id in
            (id, state == "failed" ? Result<String, HaError>.failure(HaError(unreachable)) :
                .success(raw(id, name: state == "long_names" ? longFavouriteName : favouriteNames[index % favouriteNames.count],
                             state: state != "off" && [0, 2].contains(index) ? "on" : "off")))
        })
        return mapFavouritesSnapshot(state == "setup" ? nil : config, replies: replies, now: now)
    }

    /// Lights fixtures: three on (warm), all off (calm), ten on ("+6 more"), long names, not set
    /// up, and unreachable with the ready lights kept as last known.
    static let lightStates = ["ready", "off", "overflow", "long_names", "setup", "failed"]
    private static let unreachable = "Can't reach Home Assistant"
    private static let lightNames = ["Kitchen", "Living room", "Desk lamp"]
    private static let longLightName = "Upstairs primary bedroom reading lamp"
    private static let overflowLightCount = 10

    static func lights(_ state: String) -> LightsSnapshot {
        precondition(lightStates.contains(state))
        let count = state == "overflow" ? overflowLightCount : lightNames.count
        let rows: [[String: Any]] = (0..<count).map { index in
            ["entity_id": "light.fixture_\(index + 1)",
             "name": state == "long_names" ? longLightName : lightNames[index % lightNames.count],
             "state": state == "off" ? "off" : "on", "brightness": 204, "group": false]
        }
        let json = String(data: try! JSONSerialization.data(withJSONObject: rows), encoding: .utf8)!
        let ready = mapLightsSnapshot(base, reply: .success(json), now: now)
        switch state {
        case "setup": return mapLightsSnapshot(nil, reply: .success(json), now: now)
        case "failed": return mapLightsSnapshot(base, reply: .failure(HaError(unreachable)), previous: ready, now: now)
        default: return ready
        }
    }

    /// Quick actions fixtures: four actions (calm), every other one unavailable, six ("+2 more"),
    /// long names, not set up, and unreachable with every action kept as Unavailable.
    static let quickStates = ["ready", "unavailable", "overflow", "long_names", "setup", "failed"]
    private static let quickNames = ["Movie time", "Good night", "All lights off", "Clean floor"]
    private static let longQuickName = "Upstairs primary bedroom lighting routine"
    private static let overflowQuickCount = 6

    static func quick(_ state: String) -> QuickSnapshot {
        precondition(quickStates.contains(state))
        var config = base
        let ids = fixtureIDs(domain: "script", names: quickNames,
                             count: state == "overflow" ? overflowQuickCount : quickNames.count)
        config.scriptIdsJson = String(data: try! JSONEncoder().encode(ids), encoding: .utf8)!
        let replies = Dictionary(uniqueKeysWithValues: ids.enumerated().map { index, id in
            (id, state == "failed" ? Result<String, HaError>.failure(HaError(unreachable)) :
                .success(raw(id, name: state == "long_names" ? longQuickName : quickNames[index % quickNames.count],
                             state: state == "unavailable" && index % 2 == 1 ? "unavailable" : "off")))
        })
        return mapQuickSnapshot(state == "setup" ? nil : config, replies: replies, now: now)
    }
}
