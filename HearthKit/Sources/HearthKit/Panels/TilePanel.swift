import Foundation

/// One tile in a two-panel grid (a light, a favourite, a quick action).
public struct PanelTile: Sendable, Equatable, Identifiable {
    public let id: String
    public let name: String
    /// The line under the name ("80%", "On", "Run", "Unavailable"); empty: no second line.
    public let reading: String
    /// SF Symbol name.
    public let icon: String
    /// Drawn raised and accented: switched on, or ready to run.
    public let lit: Bool
    /// Whether a tap may send its command. False for anything unavailable or last known.
    public let live: Bool
    /// The state a tap asks for, fixed when the tile is drawn.
    public let turnOn: Bool
    /// The light's own colour, when it has one.
    public let accentARGB: UInt32?

    public init(id: String, name: String, reading: String, icon: String, lit: Bool, live: Bool,
                turnOn: Bool, accentARGB: UInt32? = nil) {
        self.id = id; self.name = name; self.reading = reading; self.icon = icon
        self.lit = lit; self.live = live; self.turnOn = turnOn; self.accentARGB = accentARGB
    }
}

/// Everything a tile-grid widget draws: Lights, Quick actions, Favourites.
public struct TilePanel: Sendable, Equatable {
    public let rail: PanelRail
    /// Shown in place of the tiles; nil: the tiles are shown.
    public let prompt: PanelPrompt?
    /// The line under the header beside the tiles ("Can't reach Home Assistant").
    public let notice: String?
    /// Every tile in display order; the view pages them (`panelPage`).
    public let tiles: [PanelTile]
    /// The time after "Checked"; nil: no stamp.
    public let checked: String?
}

/// The numbers an on/off rail is built from.
struct PanelTileCounts {
    let total: Int
    let on: Int
    let unavailable: Int

    init(_ tiles: [PanelTile]) {
        total = tiles.count
        on = tiles.filter(\.lit).count
        unavailable = tiles.filter { !$0.live }.count
    }
}

/// The rail of an on/off widget once Home Assistant has answered: "2 on" over `ofDetail`, or
/// "All off". Items that did not report are never counted as off.
func panelOnOffRail(_ counts: PanelTileCounts, onIcon: String, offIcon: String, noun: String,
                    ofDetail: String) -> PanelRail {
    if counts.on > 0 {
        return PanelRail(icon: onIcon, word: "\(counts.on) on", detail: ofDetail,
                         tone: panelOnOffTone(itemCount: counts.total, onCount: counts.on,
                                              unavailableCount: counts.unavailable))
    }
    if counts.unavailable == counts.total {
        return panelNotReportingRail(icon: offIcon, count: counts.total, noun: noun)
    }
    return PanelRail(icon: offIcon, word: "All off", detail: ofDetail,
                     tone: panelOnOffTone(itemCount: counts.total, onCount: 0,
                                          unavailableCount: counts.unavailable))
}
