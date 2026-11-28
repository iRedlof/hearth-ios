import SwiftUI
import HearthKit

/// A Quick action chip: the run glyph and the action's name, which wraps to two lines when roomy
/// so it is not cut, with "Unavailable" under it when the action cannot run.
struct BeaconPanelChip: View {
    let tile: PanelTile
    let roomy: Bool
    let look: BeaconLook
    @Environment(\.cardTextScale) private var textScale

    private var ink: Color { Color(argb: look.ink) }

    var body: some View {
        HStack(spacing: PanelMetrics.tileGlyphGap) {
            Image(systemName: tile.icon).font(.system(size: PanelMetrics.tileGlyphSize, weight: .semibold))
                .foregroundStyle(ink.opacity(tile.live ? PanelMetrics.secondaryOpacity : PanelMetrics.dimGlyphOpacity))
            VStack(alignment: .leading, spacing: 0) {
                Text(tile.name).font(HearthFont.footnote.font(scale: textScale).weight(.semibold))
                    .foregroundStyle(ink).multilineTextAlignment(.leading)
                    .lineLimit(roomy ? PanelMetrics.chipRoomyNameLines : 1)
                    .minimumScaleFactor(PanelMetrics.nameShrink)
                    .fixedSize(horizontal: false, vertical: true)
                if !tile.reading.isEmpty {
                    Text(tile.reading).font(HearthFont.caption.font(scale: textScale))
                        .foregroundStyle(ink.opacity(PanelMetrics.secondaryOpacity)).lineLimit(1)
                        .minimumScaleFactor(PanelMetrics.nameShrink)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, PanelMetrics.tileHorizontalPadding)
        .padding(.vertical, PanelMetrics.chipVerticalPadding)
        .frame(maxWidth: .infinity, minHeight: PanelMetrics.chipMinimumHeight,
               maxHeight: PanelMetrics.chipMaximumHeight, alignment: .leading)
        .background(Color(argb: tile.lit ? look.chip : look.chipFaint),
                    in: RoundedRectangle(cornerRadius: PanelMetrics.tileRadius))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(tile.reading.isEmpty ? tile.name : "\(tile.name), \(tile.reading)")
    }
}
