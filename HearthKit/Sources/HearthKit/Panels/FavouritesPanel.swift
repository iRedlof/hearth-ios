import Foundation

private enum FavouritesPanelCopy {
    static let icon = "star.fill"
    static let noun = "favourite"
    static let none = "None yet"
    static let chooseDetail = "Choose favourites"
    static let choose = "Choose your favourites"
    static let empty = "No favourites found"
    static let run = "Run"
}

/// The Favourites widget: "2 on" over "of 4" on the rail, up to four tiles in the body that toggle
/// (or run, for a script).
public func favouritesPanel(_ snap: FavSnapshot) -> TilePanel {
    let unreachable = snap.state == .failed
    let tiles = snap.items.map { favouriteTile($0, unreachable: unreachable) }
    let prompt = panelPrompt(state: snap.state, error: snap.error, hasItems: !tiles.isEmpty,
                             choice: FavouritesPanelCopy.choose, empty: FavouritesPanelCopy.empty)
    return TilePanel(rail: favouritesRail(snap.state, tiles: tiles), prompt: prompt,
                     notice: panelNotice(error: snap.error, prompt: prompt), tiles: tiles,
                     checked: panelCheckedTime(snap.checkedAt))
}

/// A favourite is live only when it reported and Home Assistant answered; otherwise it is last
/// known: dimmed, "Unavailable", and not tappable.
private func favouriteTile(_ fav: Fav, unreachable: Bool) -> PanelTile {
    let live = fav.available && !unreachable
    let reading = fav.domain == "script" ? FavouritesPanelCopy.run : (fav.on ? "On" : "Off")
    return PanelTile(id: fav.id, name: fav.name, reading: live ? reading : PanelCopy.unavailable,
                     icon: favouriteIcon(domain: fav.domain), lit: live && fav.on, live: live,
                     turnOn: fav.requestedOn)
}

/// The glyph for a favourite's kind of entity.
public func favouriteIcon(domain: String) -> String {
    switch domain {
    case "light": "lightbulb.fill"
    case "fan": "fanblades.fill"
    case "input_boolean": "switch.2"
    case "script": "play.circle.fill"
    default: "power"   // switch
    }
}

private func favouritesRail(_ state: TileSnapshotState, tiles: [PanelTile]) -> PanelRail {
    let icon = FavouritesPanelCopy.icon
    let counts = PanelTileCounts(tiles)
    switch state {
    case .setup:
        return panelSetupRail(icon: icon)
    case .loading:
        return panelCheckingRail(icon: icon)
    case .failed:
        return panelNotReportingRail(icon: icon, count: counts.total, noun: FavouritesPanelCopy.noun)
    case .choose, .ready, .empty:
        guard counts.total > 0 else {
            return PanelRail(icon: icon, word: FavouritesPanelCopy.none,
                             detail: FavouritesPanelCopy.chooseDetail, tone: PanelTone.neutral)
        }
        return panelOnOffRail(counts, onIcon: icon, offIcon: icon, noun: FavouritesPanelCopy.noun,
                              ofDetail: "of \(counts.total)")
    }
}
