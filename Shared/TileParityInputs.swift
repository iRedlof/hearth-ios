import Foundation
import HearthKit

/// Explicit raw replies feed the same mappers as the live providers. The catalog blocks all input.
enum TileParityInputs {
    static let states = ["setup", "loading", "empty", "ready", "unavailable", "failed", "overflow",
                         "long_names", "pinned_overflow", "pins_only", "one_pin", "overflow_error"]
    private static let now = Date(timeIntervalSince1970: 1_793_379_600)
    private static let base = HaConfig(baseUrl: "https://example.com", token: "inert", entityId: "")

    private static func raw(_ id: String, name: String, state: String) -> String {
        let object: [String: Any] = ["entity_id": id, "state": state, "attributes": ["friendly_name": name]]
        return String(data: try! JSONSerialization.data(withJSONObject: object), encoding: .utf8)!
    }

    static func favourites(_ state: String) -> FavSnapshot {
        if state == "loading" { return .loading }
        var config = base
        let count = state == "overflow" || state == "overflow_error" ? 12 : 4
        let ids = (1...count).map { "switch.fixture_\($0)" }
        config.favouriteIdsJson = state == "empty" ? "[]" : String(data: try! JSONEncoder().encode(ids), encoding: .utf8)!
        let replies = Dictionary(uniqueKeysWithValues: ids.enumerated().map { index, id in
            (id, state == "failed" || state == "overflow_error" && index == 0 ? Result<String, HaError>.failure(HaError("Can't reach Home Assistant")) :
                .success(raw(id, name: state == "long_names" ? "Upstairs primary bedroom reading lamp" : ["Coffee maker", "Bedroom fan", "Corner lamp", "Guest mode"][index % 4],
                             state: state == "unavailable" && index == 1 ? "unavailable" : index % 2 == 0 ? "on" : "off")))
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

    static func quick(_ state: String) -> QuickSnapshot {
        if state == "loading" { return .loading }
        var config = base
        let count = state == "overflow" || state == "overflow_error" ? 6 : 4
        let ids = (1...count).map { "script.fixture_\($0)" }
        config.scriptIdsJson = state == "empty" ? "[]" : String(data: try! JSONEncoder().encode(ids), encoding: .utf8)!
        let replies = Dictionary(uniqueKeysWithValues: ids.enumerated().map { index, id in
            (id, state == "failed" || state == "overflow_error" && index == 0 ? Result<String, HaError>.failure(HaError("Can't reach Home Assistant")) :
                .success(raw(id, name: state == "long_names" ? "Upstairs primary bedroom lighting routine" : ["Movie time", "Good night", "All lights off", "Clean floor"][index % 4],
                             state: state == "unavailable" && index % 2 == 1 ? "unavailable" : "off")))
        })
        return mapQuickSnapshot(state == "setup" ? nil : config, replies: replies, now: now)
    }
}
