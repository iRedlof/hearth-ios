import SwiftUI
import HearthKit

/// A grid tile for a light or a favourite: its glyph, its name, and its reading ("80%", "On",
/// "Unavailable"). Roomy puts the glyph above the name, as pictured; otherwise the glyph sits
/// before the reading and the tile is one line shorter. Either way the name has the tile's width.
struct BeaconPanelTile: View {
    let tile: PanelTile
    let roomy: Bool
    let look: BeaconLook
    @Environment(\.cardTextScale) private var textScale

    private var ink: Color { Color(argb: look.ink) }
    /// A light's own colour, else the body's warm accent.
    private var accent: Color { Color(argb: tile.accentARGB ?? look.heat) }

    var body: some View {
        content
            .padding(.horizontal, PanelMetrics.tileHorizontalPadding)
            .padding(.vertical, PanelMetrics.tileVerticalPadding)
            .frame(maxWidth: .infinity, maxHeight: PanelMetrics.tileMaximumHeight, alignment: .leading)
            .background(Color(argb: tile.lit ? look.chip : look.chipFaint),
                        in: RoundedRectangle(cornerRadius: PanelMetrics.tileRadius))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(tile.name), \(tile.reading)")
    }

    @ViewBuilder private var content: some View {
        if roomy {
            VStack(alignment: .leading, spacing: PanelMetrics.tileLineGap) {
                glyph
                Spacer(minLength: 0)
                name
                reading
            }
        } else {
            VStack(alignment: .leading, spacing: PanelMetrics.tileLineGap) {
                name
                HStack(spacing: PanelMetrics.tileGlyphGap) { glyph; reading }
            }
        }
    }

    private var glyph: some View {
        Image(systemName: tile.icon).font(.system(size: PanelMetrics.tileGlyphSize, weight: .semibold))
            .foregroundStyle(tile.lit ? accent : ink.opacity(PanelMetrics.dimGlyphOpacity))
    }

    private var name: some View {
        Text(tile.name).font(HearthFont.footnote.font(scale: textScale).weight(.semibold))
            .foregroundStyle(ink).lineLimit(1).minimumScaleFactor(PanelMetrics.nameShrink)
    }

    private var reading: some View {
        Text(tile.reading).font(HearthFont.caption.font(scale: textScale))
            .foregroundStyle(ink.opacity(PanelMetrics.secondaryOpacity)).lineLimit(1)
            .minimumScaleFactor(PanelMetrics.nameShrink)
    }
}
