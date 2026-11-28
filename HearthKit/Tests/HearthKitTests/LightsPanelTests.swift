import Testing
import Foundation
@testable import HearthKit

private let unreachable = "Can't reach Home Assistant"
private let now = Date(timeIntervalSince1970: 1_793_379_600)

private func lights(_ list: [Light], state: TileSnapshotState = .ready, error: String? = nil,
                    pinned: Set<String> = []) -> LightsSnapshot {
    LightsSnapshot(summary: lightsSummary(list, now: now, pinned: pinned), checkedAt: "10:00 AM",
                   state: state, error: error)
}

@Suite("Lights two-panel")
struct LightsPanelTests {
    private let three = [
        Light(id: "light.desk", name: "Desk lamp", on: true, percent: 80, since: nil),
        Light(id: "light.kitchen", name: "Kitchen", on: true, percent: nil, since: nil, rgb: 0xFF7FB0FF),
        Light(id: "light.living", name: "Living room", on: false, percent: nil, since: nil),
    ]

    @Test("Lights on: a warm rail counting them out of all lights")
    func someOn() {
        let panel = lightsPanel(lights(three))
        #expect(panel.rail == PanelRail(icon: "lightbulb.fill", word: "2 on", detail: "of 3 lights", tone: .warn))
        #expect(panel.prompt == nil)
        #expect(panel.notice == nil)
        #expect(panel.checked == "10:00 AM")
    }

    @Test("Lit lights come first, then pinned, then the rest; each tile carries its toggle target")
    func tiles() {
        let panel = lightsPanel(lights(three, pinned: ["light.living"]))
        #expect(panel.tiles.map(\.id) == ["light.desk", "light.kitchen", "light.living"])
        #expect(panel.tiles.map(\.reading) == ["80%", "On", "Off"])
        #expect(panel.tiles.map(\.lit) == [true, true, false])
        #expect(panel.tiles.map(\.turnOn) == [false, false, true])
        #expect(panel.tiles.allSatisfy { $0.live })
        #expect(panel.tiles.map(\.icon) == ["lightbulb.fill", "lightbulb.fill", "lightbulb"])
        #expect(panel.tiles.map(\.accentARGB) == [nil, 0xFF7FB0FF, nil])
    }

    @Test("A medium body holds four lights, then says how many more")
    func paging() {
        let many = (0..<10).map { Light(id: "light.\($0)", name: "Light \($0)", on: true, percent: nil, since: nil) }
        let panel = lightsPanel(lights(many, pinned: ["light.9"]))
        #expect(panel.rail.word == "10 on")
        #expect(panel.rail.detail == "of 10 lights")
        let page = panelPage(panel.tiles, limit: PanelLimits.maxTiles)
        #expect(page.shown.map(\.id) == ["light.0", "light.1", "light.2", "light.3"])
        #expect(page.moreLabel == "+6 more")
        let oneRow = panelPage(panel.tiles, limit: PanelTileFit(rows: 1, roomy: false).tileLimit)
        #expect(oneRow.shown.count == 2)
        #expect(oneRow.moreLabel == "+8 more")
    }

    @Test("All off is calm")
    func allOff() {
        let panel = lightsPanel(lights(three.map {
            Light(id: $0.id, name: $0.name, on: false, percent: nil, since: nil)
        }))
        #expect(panel.rail == PanelRail(icon: "lightbulb", word: "All off", detail: "of 3 lights", tone: .calm))
    }

    @Test("One light reads in the singular")
    func singular() {
        let panel = lightsPanel(lights([three[0]]))
        #expect(panel.rail.word == "1 on")
        #expect(panel.rail.detail == "of 1 light")
    }

    @Test("Not set up")
    func setup() {
        let panel = lightsPanel(LightsSnapshot(summary: lightsSummary([], now: now), checkedAt: "", state: .setup))
        #expect(panel.rail == panelSetupRail(icon: "lightbulb.fill"))
        #expect(panel.prompt == PanelPrompt(message: "Connect Home Assistant", action: .connect))
        #expect(panel.tiles.isEmpty)
        #expect(panel.checked == nil)
    }

    @Test("Unreachable keeps the last-known lights, unavailable and not tappable, on a neutral rail")
    func failed() {
        let lastKnown = three.map { Light(id: $0.id, name: $0.name, on: false, percent: nil, since: nil, available: false) }
        let panel = lightsPanel(LightsSnapshot(summary: lightsSummary(lastKnown, now: now), checkedAt: "",
                                               state: .failed, error: unreachable))
        #expect(panel.rail == PanelRail(icon: "lightbulb", word: "3 not reporting", detail: "3 lights", tone: .unknown))
        #expect(panel.notice == unreachable)
        #expect(panel.prompt == nil)
        #expect(panel.tiles.count == 3)
        #expect(panel.tiles.allSatisfy { $0.reading == "Unavailable" && !$0.live && !$0.lit })
        #expect(panel.checked == nil)
    }

    @Test("A failed snapshot never offers a toggle, even for a light it still calls available")
    func failedNeverLive() {
        let panel = lightsPanel(lights(three, state: .failed, error: unreachable))
        #expect(panel.tiles.allSatisfy { !$0.live && $0.reading == "Unavailable" })
        #expect(panel.rail.word == "3 not reporting")
    }

    @Test("Unreachable with nothing last known says the read failed")
    func failedEmpty() {
        let panel = lightsPanel(lights([], state: .failed, error: unreachable))
        #expect(panel.rail == PanelRail(icon: "lightbulb", word: "Can't read", detail: "Home is unreachable", tone: .unknown))
        #expect(panel.prompt == PanelPrompt(message: unreachable, action: nil))
        #expect(panel.notice == nil)
    }

    @Test("Lights that stopped reporting are never counted as off")
    func unavailable() {
        let list = three.map { Light(id: $0.id, name: $0.name, on: false, percent: nil, since: nil, available: false) }
        let all = lightsPanel(lights(list))
        #expect(all.rail == PanelRail(icon: "lightbulb", word: "3 not reporting", detail: "3 lights", tone: .unknown))
        let some = lightsPanel(lights([list[0], Light(id: "light.x", name: "X", on: false, percent: nil, since: nil)]))
        #expect(some.rail == PanelRail(icon: "lightbulb", word: "All off", detail: "of 2 lights", tone: .unknown))
    }

    @Test("Loading and an empty home")
    func passive() {
        #expect(lightsPanel(.loading).rail == panelCheckingRail(icon: "lightbulb"))
        #expect(lightsPanel(.loading).prompt == PanelPrompt(message: "Checking…", action: nil))
        let empty = lightsPanel(lights([], state: .empty))
        #expect(empty.rail == PanelRail(icon: "lightbulb", word: "No lights", detail: "", tone: .unknown))
        #expect(empty.prompt == PanelPrompt(message: "No lights found", action: nil))
    }
}
