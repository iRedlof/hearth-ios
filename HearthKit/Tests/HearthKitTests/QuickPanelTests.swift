import Testing
import Foundation
@testable import HearthKit

private let unreachable = "Can't reach Home Assistant"

@Suite("Quick actions two-panel")
struct QuickPanelTests {
    private let keys = [
        QuickKey(id: "script.movie", name: "Movie time"), QuickKey(id: "script.night", name: "Good night"),
        QuickKey(id: "script.off", name: "All lights off"), QuickKey(id: "script.clean", name: "Clean floor"),
    ]

    @Test("Ready: a calm rail counting the actions")
    func ready() {
        let panel = quickPanel(QuickSnapshot(keys: keys, checkedAt: "10:00 AM"))
        #expect(panel.rail == PanelRail(icon: "bolt.fill", word: "4 actions", detail: "Tap to run", tone: .calm))
        #expect(panel.tiles.map(\.id) == keys.map(\.id))
        #expect(panel.tiles.allSatisfy { $0.live && $0.lit && $0.reading.isEmpty && $0.turnOn })
        #expect(panel.tiles.allSatisfy { $0.icon == "play.circle.fill" })
        #expect(panel.checked == "10:00 AM")
        #expect(quickPanel(QuickSnapshot(keys: [keys[0]], checkedAt: "")).rail.word == "1 action")
    }

    @Test("An action whose script stopped reporting says so and cannot run")
    func oneUnavailable() {
        let panel = quickPanel(QuickSnapshot(keys: [keys[0], QuickKey(id: "script.night", name: "Good night", available: false)],
                                             checkedAt: "10:00 AM"))
        #expect(panel.rail.word == "2 actions")
        #expect(panel.tiles.map(\.live) == [true, false])
        #expect(panel.tiles.map(\.reading) == ["", "Unavailable"])
    }

    @Test("Unreachable: can't run, every action unavailable")
    func failed() {
        let lastKnown = keys.map { QuickKey(id: $0.id, name: $0.name, available: false) }
        let panel = quickPanel(QuickSnapshot(keys: lastKnown, checkedAt: "", state: .failed, error: unreachable))
        #expect(panel.rail == PanelRail(icon: "bolt.fill", word: "Can't run", detail: "Home is unreachable", tone: .unknown))
        #expect(panel.notice == unreachable)
        #expect(panel.tiles.count == 4)
        #expect(panel.tiles.allSatisfy { !$0.live && $0.reading == "Unavailable" })
        let stillAvailable = quickPanel(QuickSnapshot(keys: keys, checkedAt: "", state: .failed, error: unreachable))
        #expect(stillAvailable.tiles.allSatisfy { !$0.live })
    }

    @Test("Not set up, nothing chosen, loading")
    func prompts() {
        let setup = quickPanel(QuickSnapshot(keys: [], checkedAt: "", state: .setup))
        #expect(setup.rail == panelSetupRail(icon: "bolt.fill"))
        #expect(setup.prompt == PanelPrompt(message: "Connect Home Assistant", action: .connect))
        let choose = quickPanel(QuickSnapshot(keys: [], checkedAt: "", state: .choose))
        #expect(choose.rail == PanelRail(icon: "bolt.fill", word: "No actions", detail: "Choose scripts", tone: .unknown))
        #expect(choose.prompt == PanelPrompt(message: "Choose your scripts", action: .openSettings))
        #expect(quickPanel(.loading).rail == panelCheckingRail(icon: "bolt.fill"))
    }

    @Test("Ready but none can run is neutral, not calm")
    func noneRunnable() {
        let panel = quickPanel(QuickSnapshot(keys: keys.map { QuickKey(id: $0.id, name: $0.name, available: false) },
                                             checkedAt: "10:00 AM"))
        #expect(panel.rail == PanelRail(icon: "bolt.fill", word: "Can't run", detail: "4 unavailable", tone: .unknown))
    }
}
