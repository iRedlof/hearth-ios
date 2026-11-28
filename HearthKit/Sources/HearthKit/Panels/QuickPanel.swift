import Foundation

private enum QuickPanelCopy {
    static let icon = "bolt.fill"
    static let keyIcon = "play.circle.fill"
    static let noun = "action"
    static let cantRun = "Can't run"
    static let tapToRun = "Tap to run"
    static let none = "No actions"
    static let chooseDetail = "Choose scripts"
    static let choose = "Choose your scripts"
    static let empty = "No scripts found"
}

/// The Quick actions widget: "4 actions" on the rail, up to four script chips in the body.
public func quickPanel(_ snap: QuickSnapshot) -> TilePanel {
    let unreachable = snap.state == .failed
    let tiles = snap.keys.map { quickTile($0, unreachable: unreachable) }
    let prompt = panelPrompt(state: snap.state, error: snap.error, hasItems: !tiles.isEmpty,
                             choice: QuickPanelCopy.choose, empty: QuickPanelCopy.empty)
    return TilePanel(rail: quickRail(snap.state, tiles: tiles), prompt: prompt,
                     notice: panelNotice(error: snap.error, prompt: prompt), tiles: tiles,
                     checked: panelCheckedTime(snap.checkedAt))
}

/// An action can run only when its script reported and Home Assistant answered; otherwise the chip
/// keeps its name, says "Unavailable", and is not tappable.
private func quickTile(_ key: QuickKey, unreachable: Bool) -> PanelTile {
    let runnable = key.available && !unreachable
    return PanelTile(id: key.id, name: key.name, reading: runnable ? "" : PanelCopy.unavailable,
                     icon: QuickPanelCopy.keyIcon, lit: runnable, live: runnable, turnOn: true)
}

private func quickRail(_ state: TileSnapshotState, tiles: [PanelTile]) -> PanelRail {
    let icon = QuickPanelCopy.icon
    switch state {
    case .setup:
        return panelSetupRail(icon: icon)
    case .loading:
        return panelCheckingRail(icon: icon)
    case .failed:
        return PanelRail(icon: icon, word: QuickPanelCopy.cantRun, detail: PanelCopy.homeUnreachable,
                         tone: PanelTone.neutral)
    case .choose, .ready, .empty:
        guard !tiles.isEmpty else {
            return PanelRail(icon: icon, word: QuickPanelCopy.none,
                             detail: state == .choose ? QuickPanelCopy.chooseDetail : "", tone: PanelTone.neutral)
        }
        guard tiles.contains(where: \.live) else {
            return PanelRail(icon: icon, word: QuickPanelCopy.cantRun,
                             detail: "\(tiles.count) \(PanelCopy.unavailable.lowercased())", tone: PanelTone.neutral)
        }
        return PanelRail(icon: icon, word: PanelCopy.counted(tiles.count, QuickPanelCopy.noun),
                         detail: QuickPanelCopy.tapToRun, tone: PanelTone.settled)
    }
}
