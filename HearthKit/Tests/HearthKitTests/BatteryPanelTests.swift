import Testing
import Foundation
@testable import HearthKit

private let unreachable = "Can't reach Home Assistant"

@Suite("Batteries two-panel")
struct BatteryPanelTests {
    private func snapshot(_ levels: [Int?], state: TileSnapshotState = .ready, error: String? = nil) -> BatterySnapshot {
        let names = ["Front Door Lock", "Backyard Motion", "Living Room Remote", "Garage Sensor", "Office Thermometer"]
        let batteries = levels.enumerated().map { index, level in
            Battery(id: "sensor.b\(index)", name: names[index % names.count], level: level,
                    state: level == nil ? "unavailable" : nil)
        }
        return BatterySnapshot(summary: batterySummary(batteries), checkedAt: "9:41 AM", state: state, error: error)
    }

    @Test("All good is green and counts what is tracked")
    func allGood() {
        let panel = batteryPanel(snapshot([92, 78, 64, 88]))
        #expect(panel.rail == PanelRail(icon: "battery.100", word: "All good", detail: "4 tracked", tone: .calm))
        #expect(panel.rows.map(\.name) == ["Living Room Remote", "Backyard Motion", "Garage Sensor", "Front Door Lock"])
        #expect(panel.rows.map(\.reading) == ["64%", "78%", "88%", "92%"])
        #expect(panel.rows.allSatisfy { $0.tone == .normal })
        #expect(panel.prompt == nil)
        #expect(panel.checked == "9:41 AM")
    }

    @Test("Low is amber and names what is low")
    func low() {
        let panel = batteryPanel(snapshot([24, 61, 88, nil]))
        #expect(panel.rail == PanelRail(icon: "battery.25", word: "1 low",
                                        detail: "Front Door Lock 24% · 1 unavailable", tone: .warn))
        #expect(panel.rows.map(\.tone) == [.low, .unavailable, .normal, .normal])
        #expect(panel.rows.map(\.reading) == ["24%", "Unavailable", "61%", "88%"])
        #expect(panel.rows.map(\.emphasised) == [true, false, false, false])
    }

    @Test("A nearly empty battery reads red in its row; the rail stays amber")
    func empty() {
        let panel = batteryPanel(snapshot([9, 24, 61]))
        #expect(panel.rail.word == "2 low")
        #expect(panel.rail.tone == .warn)
        #expect(panel.rows.map(\.tone) == [.empty, .low, .normal])
    }

    @Test("Batteries that stopped reporting, with none low, are neutral")
    func unavailableOnly() {
        let panel = batteryPanel(snapshot([nil, 61]))
        #expect(panel.rail == PanelRail(icon: "battery.100", word: "1 unavailable", detail: "2 tracked", tone: .unknown))
    }

    @Test("Unreachable keeps the last-known answer and levels on a neutral rail")
    func failed() {
        let panel = batteryPanel(snapshot([9, 24, 61, 88], state: .failed, error: unreachable))
        #expect(panel.rail == PanelRail(icon: "battery.25", word: "2 low",
                                        detail: "Front Door Lock 9%, Backyard Motion 24%", tone: .unknown))
        #expect(panel.notice == unreachable)
        #expect(panel.rows.map(\.reading) == ["9%", "24%", "61%", "88%"])
        #expect(panel.checked == "9:41 AM")
    }

    @Test("Unreachable with nothing last known")
    func failedEmpty() {
        let panel = batteryPanel(BatterySnapshot(summary: batterySummary([]), checkedAt: "", state: .failed, error: unreachable))
        #expect(panel.rail == PanelRail(icon: "battery.25", word: "No reading", detail: "Home is unreachable", tone: .unknown))
        #expect(panel.prompt == PanelPrompt(message: unreachable, action: nil))
        #expect(panel.checked == nil)
    }

    @Test("Not set up, loading, none found")
    func prompts() {
        let setup = batteryPanel(BatterySnapshot(summary: batterySummary([]), checkedAt: "", state: .setup))
        #expect(setup.rail == panelSetupRail(icon: "minus.plus.batteryblock.fill"))
        #expect(setup.prompt == PanelPrompt(message: "Connect Home Assistant", action: .connect))
        #expect(batteryPanel(.loading).rail == panelCheckingRail(icon: "battery.100"))
        let none = batteryPanel(BatterySnapshot(summary: batterySummary([]), checkedAt: "9:41 AM", state: .empty))
        #expect(none.rail == PanelRail(icon: "battery.100", word: "No batteries", detail: "", tone: .unknown))
        #expect(none.prompt == PanelPrompt(message: "No batteries found", action: nil))
    }

    @Test("Three rows, then how many more")
    func paging() {
        let page = panelPage(batteryPanel(snapshot([92, 78, 64, 88])).rows, limit: PanelLimits.maxRows)
        #expect(page.shown.count == 3)
        #expect(page.moreLabel == "+1 more")
    }
}
