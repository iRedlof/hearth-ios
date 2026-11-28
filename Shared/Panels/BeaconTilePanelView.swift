import SwiftUI
import AppIntents
import HearthKit

/// How a tile-grid widget draws its tiles.
enum BeaconTileShape {
    /// Glyph, name and reading (Lights, Favourites).
    case tile
    /// Run glyph and a name that may take two lines (Quick actions).
    case chip
}

/// A tile-grid two-panel widget (Lights, Quick actions, Favourites) drawn from its `TilePanel`.
/// `intent` is the command a live tile sends; a tile that is not live is drawn but takes no tap.
///
/// The grid fits the height it is given: all four tiles as pictured, then all four in the shorter
/// form, then a single row (`PanelTileFit`), with "+N more" for what is left out.
struct BeaconTilePanelView<Intent: AppIntent>: View {
    let panel: TilePanel
    let title: String
    let kind: String
    let shape: BeaconTileShape
    let intent: (PanelTile) -> Intent
    @Environment(\.cardStyle) private var cardStyle

    private var look: BeaconLook { beaconLook(cardStyle) }

    var body: some View {
        BeaconTwoPanel {
            BeaconStatusRail(panel.rail)
        } surface: {
            BeaconPanelBody(title: title, kind: kind, checked: panel.checked, notice: panel.notice,
                            prompt: panel.prompt) {
                ViewThatFits(in: .vertical) {
                    ForEach(PanelTileFit.choices, id: \.self) { grid($0) }
                }
            }
        }
    }

    private func grid(_ fit: PanelTileFit) -> some View {
        let page = panelPage(panel.tiles, limit: fit.tileLimit)
        return VStack(alignment: .leading, spacing: PanelMetrics.moreGap) {
            BeaconTileGrid(tiles: page.shown) { cell($0, roomy: fit.roomy) }
            if let more = page.moreLabel {
                BeaconPanelMore(label: more, opensSettings: true, ink: Color(argb: look.ink))
            }
        }
    }

    @ViewBuilder private func cell(_ tile: PanelTile, roomy: Bool) -> some View {
        if tile.live {
            Button(intent: intent(tile)) { label(tile, roomy: roomy) }.buttonStyle(.plain)
        } else {
            label(tile, roomy: roomy)
        }
    }

    @ViewBuilder private func label(_ tile: PanelTile, roomy: Bool) -> some View {
        switch shape {
        case .tile: BeaconPanelTile(tile: tile, roomy: roomy, look: look)
        case .chip: BeaconPanelChip(tile: tile, roomy: roomy, look: look)
        }
    }
}
