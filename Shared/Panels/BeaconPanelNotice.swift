import SwiftUI
import HearthKit

/// The line under the header when the items below are last known: a clock and why the read
/// failed ("Can't reach Home Assistant").
struct BeaconPanelNotice: View {
    let message: String
    let ink: Color
    @Environment(\.cardTextScale) private var textScale

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "clock").font(HearthFont.caption.font)
            Text(message).font(HearthFont.caption.font(scale: textScale))
                .lineLimit(1).minimumScaleFactor(PanelMetrics.nameShrink)
        }
        .foregroundStyle(ink.opacity(PanelMetrics.secondaryOpacity))
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(message)
    }
}
