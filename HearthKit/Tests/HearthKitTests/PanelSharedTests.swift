import Testing
import Foundation
@testable import HearthKit

@Suite("Two-panel widgets: shared decisions")
struct PanelSharedTests {
    @Test("The rail reuses the existing tone values and invents none")
    func tones() {
        #expect(PanelTone.active == .warn)
        #expect(PanelTone.settled == .calm)
        #expect(PanelTone.neutral == .unknown)
    }

    @Test("Something on is warm, everything off is calm, nothing to judge is neutral")
    func onOffTone() {
        #expect(panelOnOffTone(itemCount: 4, onCount: 2, unavailableCount: 0) == .warn)
        #expect(panelOnOffTone(itemCount: 4, onCount: 0, unavailableCount: 0) == .calm)
        #expect(panelOnOffTone(itemCount: 4, onCount: 0, unavailableCount: 1) == .unknown)
        #expect(panelOnOffTone(itemCount: 0, onCount: 0, unavailableCount: 0) == .unknown)
    }

    @Test("Not set up reads the same on every rail")
    func setupRail() {
        let rail = panelSetupRail(icon: "bolt.fill")
        #expect(rail == PanelRail(icon: "bolt.fill", word: "Set up", detail: "Tap to connect", tone: .unknown))
    }

    @Test("Unreachable says how many are not reporting, or that the read failed when none is known")
    func notReporting() {
        #expect(panelNotReportingRail(icon: "lightbulb", count: 3, noun: "light")
            == PanelRail(icon: "lightbulb", word: "3 not reporting", detail: "3 lights", tone: .unknown))
        #expect(panelNotReportingRail(icon: "star.fill", count: 1, noun: "favourite").detail == "1 favourite")
        #expect(panelNotReportingRail(icon: "lightbulb", count: 0, noun: "light")
            == PanelRail(icon: "lightbulb", word: "Can't read", detail: "Home is unreachable", tone: .unknown))
    }

    @Test("A long answer may take two lines; a short one stays on one")
    func wordLines() {
        #expect(PanelRail(icon: "", word: "3 on", detail: "", tone: .warn).wordLines == 1)
        #expect(PanelRail(icon: "", word: "4 actions", detail: "", tone: .calm).wordLines == 1)
        #expect(PanelRail(icon: "", word: "3 not reporting", detail: "", tone: .unknown).wordLines == 2)
    }

    @Test("No check time prints no stamp, never a dash")
    func checkedTime() {
        #expect(panelCheckedTime("9:41 AM") == "9:41 AM")
        #expect(panelCheckedTime("") == nil)
        #expect(panelCheckedTime("  ") == nil)
        #expect(panelCheckedTime("—") == nil)
    }

    @Test("A page keeps the first items and counts the rest")
    func page() {
        let page = panelPage(["a", "b", "c", "d", "e", "f"], limit: 4)
        #expect(page.shown == ["a", "b", "c", "d"])
        #expect(page.hiddenCount == 2)
        #expect(page.moreLabel == "+2 more")
        let all = panelPage(["a", "b"], limit: 4)
        #expect(all.shown == ["a", "b"])
        #expect(all.hiddenCount == 0)
        #expect(all.moreLabel == nil)
        #expect(panelPage(["a"], limit: 0).shown.isEmpty)
        #expect(panelPage(["a"], limit: -3).hiddenCount == 1)
    }

    @Test("A medium body holds four tiles or three rows")
    func limits() {
        #expect(PanelLimits.tileColumns == 2)
        #expect(PanelLimits.tileRows == 2)
        #expect(PanelLimits.maxTiles == 4)
        #expect(PanelLimits.maxRows == 3)
    }
}

@Suite("Two-panel widgets: what the body shows instead of items")
struct PanelPromptTests {
    private func prompt(_ state: TileSnapshotState, error: String? = nil, hasItems: Bool = false) -> PanelPrompt? {
        panelPrompt(state: state, error: error, hasItems: hasItems, choice: "Choose your scripts", empty: "No scripts found")
    }

    @Test("Not set up offers Connect")
    func setup() {
        #expect(prompt(.setup) == PanelPrompt(message: "Connect Home Assistant", action: .connect))
        #expect(PanelAction.connect.label == "Connect")
        #expect(!PanelAction.connect.reconnect)
    }

    @Test("Nothing chosen offers Settings")
    func choose() {
        #expect(prompt(.choose) == PanelPrompt(message: "Choose your scripts", action: .openSettings))
        #expect(PanelAction.openSettings.label == "Open Settings")
        #expect(!PanelAction.openSettings.reconnect)
    }

    @Test("Loading and an empty home say so and offer nothing")
    func passive() {
        #expect(prompt(.loading) == PanelPrompt(message: "Checking…", action: nil))
        #expect(prompt(.empty) == PanelPrompt(message: "No scripts found", action: nil))
        #expect(prompt(.ready) == PanelPrompt(message: "No scripts found", action: nil))
    }

    @Test("Items are shown whenever there are some and nothing needs the person")
    func items() {
        #expect(prompt(.ready, hasItems: true) == nil)
        #expect(prompt(.empty, hasItems: true) == nil)
        #expect(prompt(.failed, error: "Can't reach Home Assistant", hasItems: true) == nil)
    }

    @Test("A failed read with nothing last known shows its reason")
    func failedEmpty() {
        #expect(prompt(.failed, error: "Can't reach Home Assistant")
            == PanelPrompt(message: "Can't reach Home Assistant", action: nil))
        #expect(prompt(.failed) == PanelPrompt(message: "Couldn't read your home", action: nil))
    }

    @Test("A sign-in or settings failure keeps its way back into the app, even over last-known items")
    func failedNeedsPerson() {
        let signIn = prompt(.failed, error: "Sign in to Home Assistant again", hasItems: true)
        #expect(signIn == PanelPrompt(message: "Sign in to Home Assistant again", action: .signIn))
        #expect(PanelAction.signIn.label == "Sign in")
        #expect(PanelAction.signIn.reconnect)
        let settings = prompt(.failed, error: "Not found — check the entity")
        #expect(settings?.action == .openSettings)
    }

    @Test("The line under the header is the read's error, only beside items")
    func notice() {
        #expect(panelNotice(error: "Can't reach Home Assistant", prompt: nil) == "Can't reach Home Assistant")
        #expect(panelNotice(error: nil, prompt: nil) == nil)
        #expect(panelNotice(error: "Can't reach Home Assistant",
                            prompt: PanelPrompt(message: "Can't reach Home Assistant", action: nil)) == nil)
    }
}
