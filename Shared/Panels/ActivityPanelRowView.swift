import SwiftUI
import HearthKit

/// One earlier event: its time, its glyph, and what happened. The text wraps to a second line
/// rather than being cut. A time with its day ("Yest 9:30 PM") wraps under itself.
struct ActivityPanelRowView: View {
    let row: ActivityPanelRow
    let ink: Color
    @Environment(\.cardTextScale) private var textScale

    /// On one line when it fits, slightly smaller if that is all it takes, else wrapped to two.
    /// The first two test their natural width: a truncating one-line Text would always "fit".
    private var what: some View {
        ViewThatFits(in: .horizontal) {
            text(scale: 1).lineLimit(1).fixedSize()
            text(scale: PanelMetrics.activityTextShrink).lineLimit(1).fixedSize()
            text(scale: 1).lineLimit(PanelMetrics.activityTextLines)
                .minimumScaleFactor(PanelMetrics.nameShrink)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func text(scale: CGFloat) -> some View {
        Text(row.text).font(HearthFont.groupLabel.font(scale: textScale * scale))
            .foregroundStyle(ink).multilineTextAlignment(.leading)
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: PanelMetrics.activityColumnGap) {
            Text(row.time).font(HearthFont.caption.font(scale: textScale).weight(.medium))
                .foregroundStyle(ink.opacity(PanelMetrics.faintOpacity))
                .lineLimit(PanelMetrics.activityTextLines)
                .frame(width: PanelMetrics.activityTimeWidth * textScale, alignment: .leading)
            Image(systemName: row.icon).font(HearthFont.footnote.font)
                .foregroundStyle(ink.opacity(PanelMetrics.secondaryOpacity))
                .frame(width: PanelMetrics.activityGlyphWidth)
            what.frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, PanelMetrics.rowVerticalPadding)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(row.time), \(row.text)")
    }
}
