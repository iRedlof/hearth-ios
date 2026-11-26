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

    static func lights(_ state: String) -> LightsSnapshot {
        if state == "loading" { return .loading }
        let count = ["overflow", "pinned_overflow"].contains(state) ? 10 : state == "pins_only" ? 5 : state == "one_pin" ? 4 : 3
        let rows: [[String: Any]] = state == "empty" ? [] : (1...count).map {
            ["entity_id": "light.fixture_\($0)", "name": state == "long_names" ? "Upstairs primary bedroom reading lamp" : ["Kitchen", "Living room", "Desk lamp"][($0 - 1) % 3],
             "state": state == "unavailable" ? "unavailable" : "on", "brightness": 204, "group": false]
        }
        let json = String(data: try! JSONSerialization.data(withJSONObject: rows), encoding: .utf8)!
        var config = base
        if state == "pinned_overflow" { config.lightPinsJson = "[\"light.fixture_9\",\"light.fixture_10\"]" }
        if state == "pins_only" {
            config.lightPinsJson = String(data: try! JSONEncoder().encode((1...5).map { "light.fixture_\($0)" }), encoding: .utf8)!
        }
        if state == "one_pin" { config.lightPinsJson = "[\"light.fixture_4\"]" }
        return mapLightsSnapshot(state == "setup" ? nil : config,
                                 reply: state == "failed" ? .failure(HaError("Can't reach Home Assistant")) : .success(json),
                                 now: now)
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
