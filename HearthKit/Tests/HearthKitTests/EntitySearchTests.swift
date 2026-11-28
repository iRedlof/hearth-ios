import Testing
@testable import HearthKit

@Suite("Entity search")
struct EntitySearchTests {
    private let entities = [
        HaEntity(id: "light.bedroom_light", name: "Bedroom Light"),
        HaEntity(id: "light.closet_light", name: "Closet Light"),
        HaEntity(id: "light.deck_cam_light", name: "Deck Cam Light"),
        HaEntity(id: "script.all_fans_turn_off", name: "[All Fans]: Turn Off"),
        HaEntity(id: "binary_sensor.ac_on_2", name: "AC On"),
        HaEntity(id: "cover.garage", name: "Garáge Door"),
    ]

    private func ids(_ query: String) -> [String] { entitiesMatching(entities, query: query).map(\.id) }

    @Test("An empty or blank search shows everything, in order")
    func empty() {
        #expect(ids("") == entities.map(\.id))
        #expect(ids("   ") == entities.map(\.id))
    }

    @Test("Matches the name, ignoring case")
    func name() {
        #expect(ids("bed") == ["light.bedroom_light"])
        #expect(ids("LIGHT") == ["light.bedroom_light", "light.closet_light", "light.deck_cam_light"])
    }

    @Test("Matches the entity id as well")
    func id() {
        #expect(ids("ac_on_2") == ["binary_sensor.ac_on_2"])
        #expect(ids("script.") == ["script.all_fans_turn_off"])
    }

    @Test("Every word must match, in any order, across name and id")
    func words() {
        #expect(ids("light deck") == ["light.deck_cam_light"])
        #expect(ids("off fans") == ["script.all_fans_turn_off"])
        #expect(ids("deck fans").isEmpty)
    }

    @Test("Accents do not matter")
    func accents() {
        #expect(ids("garage") == ["cover.garage"])
    }

    @Test("Nothing matches")
    func none() {
        #expect(ids("zzz").isEmpty)
    }
}
