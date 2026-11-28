import Testing
import Foundation
@testable import HearthKit

private let unreachable = "Can't reach Home Assistant"

@Suite("Favourites two-panel")
struct FavouritesPanelTests {
    private let items = [
        Fav(id: "switch.coffee", name: "Coffee maker", on: true), Fav(id: "fan.bedroom", name: "Bedroom fan", on: false),
        Fav(id: "light.corner", name: "Corner lamp", on: true), Fav(id: "input_boolean.guest", name: "Guest mode", on: false),
        Fav(id: "script.movie", name: "Movie time", on: false),
    ]

    @Test("Some on: warm, counted out of all favourites")
    func ready() {
        let panel = favouritesPanel(FavSnapshot(items: items, checkedAt: "10:00 AM"))
        #expect(panel.rail == PanelRail(icon: "star.fill", word: "2 on", detail: "of 5", tone: .warn))
        #expect(panel.tiles.map(\.reading) == ["On", "Off", "On", "Off", "Run"])
        #expect(panel.tiles.map(\.icon) == ["power", "fanblades.fill", "lightbulb.fill", "switch.2", "play.circle.fill"])
        #expect(panel.tiles.map(\.lit) == [true, false, true, false, false])
        #expect(panel.tiles.map(\.turnOn) == items.map(\.requestedOn))
        #expect(panel.tiles.map(\.turnOn) == [false, true, false, true, true])
        #expect(panel.tiles.allSatisfy { $0.live })
    }

    @Test("All off is calm")
    func allOff() {
        let panel = favouritesPanel(FavSnapshot(items: [items[1], items[3]], checkedAt: "10:00 AM"))
        #expect(panel.rail == PanelRail(icon: "star.fill", word: "All off", detail: "of 2", tone: .calm))
    }

    @Test("Unreachable keeps every favourite, unavailable, on a neutral rail")
    func failed() {
        let lastKnown = items.prefix(4).map { Fav(id: $0.id, name: $0.name, on: false, available: false) }
        let panel = favouritesPanel(FavSnapshot(items: lastKnown, checkedAt: "", state: .failed, error: unreachable))
        #expect(panel.rail == PanelRail(icon: "star.fill", word: "4 not reporting", detail: "4 favourites", tone: .unknown))
        #expect(panel.notice == unreachable)
        #expect(panel.tiles.allSatisfy { !$0.live && !$0.lit && $0.reading == "Unavailable" })
    }

    @Test("One favourite that did not report is unavailable; the rest still work")
    func partial() {
        let panel = favouritesPanel(FavSnapshot(items: [items[0], Fav(id: "fan.bedroom", name: "Bedroom fan", on: false, available: false)],
                                                checkedAt: "10:00 AM", error: unreachable))
        #expect(panel.rail == PanelRail(icon: "star.fill", word: "1 on", detail: "of 2", tone: .warn))
        #expect(panel.tiles.map(\.live) == [true, false])
        #expect(panel.notice == unreachable)
    }

    @Test("Not set up and nothing chosen")
    func prompts() {
        let setup = favouritesPanel(FavSnapshot(items: [], checkedAt: "", state: .setup))
        #expect(setup.rail == panelSetupRail(icon: "star.fill"))
        let choose = favouritesPanel(FavSnapshot(items: [], checkedAt: "", state: .choose))
        #expect(choose.rail == PanelRail(icon: "star.fill", word: "None yet", detail: "Choose favourites", tone: .unknown))
        #expect(choose.prompt == PanelPrompt(message: "Choose your favourites", action: .openSettings))
    }
}
