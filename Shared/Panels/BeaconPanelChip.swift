import SwiftUI
import HearthKit

/// A Quick action chip: the run glyph and the action's name, which wraps to two lines so it is
/// not cut, with "Unavailable" under it when the action cannot run. When that is too tall the
/// chip gives up its glyph and keeps the name on one line across the whole chip.
struct BeaconPanelChip: View {
    let tile: PanelTile
    let roomy: Bool
    let look: BeaconLook
    @Environment(\.cardTextScale) private var textScale

    private var ink: Color { Color(argb: look.ink) }

    var body: some View {
        HStack(spacing: PanelMetrics.tileGlyphGap) {
            if roomy {
                Image(systemName: tile.icon).font(.system(size: PanelMetrics.tileGlyphSize, weight: .semibold))
                    .foregroundStyle(ink.opacity(tile.live ? PanelMetrics.secondaryOpacity : PanelMetrics.dimGlyphOpacity))
            }
            VStack(alignment: .leading, spacing: 0) {
                Text(tile.name).font(HearthFont.footnote.font(scale: textScale).weight(.semibold))
                    .foregroundStyle(ink).multilineTextAlignment(.leading)
                    .lineLimit(roomy ? PanelMetrics.chipRoomyNameLines : 1)
                    .minimumScaleFactor(PanelMetrics.chipNameShrink)
                    .fixedSize(horizontal: false, vertical: true)
                if !tile.reading.isEmpty {
                    Text(tile.reading).font(HearthFont.caption.font(scale: textScale))
                        .foregroundStyle(ink.opacity(PanelMetrics.secondaryOpacity)).lineLimit(1)
                        .minimumScaleFactor(PanelMetrics.nameShrink)
                }
            }
            // Not a Spacer: beside one, the name is offered only half the chip and wraps early.
            .frame(maxWidth: .infinity, alignment: .leading)
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
