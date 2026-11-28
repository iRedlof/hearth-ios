import SwiftUI
import HearthKit

/// One battery: its name, and its level in the colour of its state (amber low, red nearly empty).
struct BatteryPanelRowView: View {
    let row: BatteryPanelRow
    let look: BeaconLook
    @Environment(\.cardTextScale) private var textScale

    private var ink: Color { Color(argb: look.ink) }
    private var readingColor: Color {
        switch row.tone {
        case .normal: ink
        case .low: Color(argb: look.heat)
        case .empty: Color(argb: look.alert)
        case .unavailable: ink.opacity(PanelMetrics.secondaryOpacity)
        }
    }

    /// A level is bold; "Unavailable" is a quieter, smaller word, which leaves the name its room.
    private var readingFont: Font {
        row.tone == .unavailable
            ? HearthFont.caption.font(scale: textScale)
            : HearthFont.groupLabel.font(scale: textScale).weight(.bold)
    }

    var body: some View {
        HStack(spacing: PanelMetrics.rowColumnGap) {
            Text(row.name).font(HearthFont.groupLabel.font(scale: textScale).weight(row.emphasised ? .semibold : .regular))
                .foregroundStyle(ink).lineLimit(1).minimumScaleFactor(PanelMetrics.nameShrink)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(row.reading).font(readingFont)
                .foregroundStyle(readingColor).lineLimit(1).fixedSize()
        }
        .padding(.vertical, PanelMetrics.rowVerticalPadding)
        .frame(maxHeight: PanelMetrics.rowMaximumHeight)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(row.name), \(row.reading)")
    }
}
