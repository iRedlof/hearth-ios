import Foundation

private enum LightsPanelCopy {
    static let onIcon = "lightbulb.fill"
    static let offIcon = "lightbulb"
    static let noun = "light"
    static let none = "No lights"
    static let empty = "No lights found"
}

/// The Lights widget: "3 on" over "of 3 lights" on the rail, up to four toggling tiles in the body.
public func lightsPanel(_ snap: LightsSnapshot) -> TilePanel {
    let unreachable = snap.state == .failed
    // Lit (and unavailable) lights first, then the always-shown pins, then the rest. The summary's
    // three lists never overlap.
    let tiles = (snap.summary.on + snap.summary.pinned + snap.summary.off).map { lightTile($0, unreachable: unreachable) }
    let prompt = panelPrompt(state: snap.state, error: snap.error, hasItems: !tiles.isEmpty,
                             choice: LightsPanelCopy.empty, empty: LightsPanelCopy.empty)
    return TilePanel(rail: lightsRail(snap.state, tiles: tiles), prompt: prompt,
                     notice: panelNotice(error: snap.error, prompt: prompt), tiles: tiles,
                     checked: panelCheckedTime(snap.checkedAt))
}

/// A light is live only when it reported and Home Assistant answered; otherwise it is last known:
/// dimmed, "Unavailable", and not tappable.
private func lightTile(_ light: LightView, unreachable: Bool) -> PanelTile {
    let live = light.available && !unreachable
    let lit = live && light.on
    let reading = light.percent.map { "\($0)%" } ?? (light.on ? "On" : "Off")
    return PanelTile(id: light.id, name: light.name, reading: live ? reading : PanelCopy.unavailable,
                     icon: lit ? LightsPanelCopy.onIcon : LightsPanelCopy.offIcon, lit: lit, live: live,
                     turnOn: !light.on, accentARGB: lit ? light.rgb : nil)
}

private func lightsRail(_ state: TileSnapshotState, tiles: [PanelTile]) -> PanelRail {
    let counts = PanelTileCounts(tiles)
    switch state {
    case .setup:
        return panelSetupRail(icon: LightsPanelCopy.onIcon)
    case .loading:
        return panelCheckingRail(icon: LightsPanelCopy.offIcon)
    case .failed:
        return panelNotReportingRail(icon: LightsPanelCopy.offIcon, count: counts.total, noun: LightsPanelCopy.noun)
    case .ready, .empty, .choose:
        guard counts.total > 0 else {
            return PanelRail(icon: LightsPanelCopy.offIcon, word: LightsPanelCopy.none, detail: "", tone: PanelTone.neutral)
        }
        return panelOnOffRail(counts, onIcon: LightsPanelCopy.onIcon, offIcon: LightsPanelCopy.offIcon,
                              noun: LightsPanelCopy.noun,
                              ofDetail: "of \(PanelCopy.counted(counts.total, LightsPanelCopy.noun))")
    }
}
