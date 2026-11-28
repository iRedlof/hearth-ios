import SwiftUI
import HearthKit

/// One of the Alarm card's two compact door rows: icon and name on the first line, a one-line
/// status under it, and a trailing control. Every size comes from `AlarmDoorRowsLayout` in exact
/// points, so both rows fit the medium widget whatever the card's text size.
struct AlarmCompactDoorRow<Trailing: View>: View {
    let icon: String
    let name: String
    /// Longest first; the first that fits the row is shown (`alarmDoorStatusLines`).
    let statusLines: [String]
    let statusColor: Color
    let ink: Color
    let fill: Color
    let layout: AlarmDoorRowsLayout
    let accessibilityText: String
    @ViewBuilder let trailing: () -> Trailing

    private typealias Metrics = AlarmDoorRowsMetrics

    var body: some View {
        HStack(spacing: Metrics.contentSpacing) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: Metrics.iconSpacing) {
                    Image(systemName: icon)
                        .font(.system(size: layout.nameSize * Metrics.iconScale, weight: .semibold))
                        .foregroundStyle(ink.opacity(0.9))
                    Text(name)
                        .font(HearthFont.groupLabel.font(fixedSize: layout.nameSize).weight(.semibold))
                        .foregroundStyle(ink).lineLimit(1).minimumScaleFactor(Metrics.nameShrink)
                }
                status
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            trailing()
        }
        .padding(.horizontal, Metrics.rowHorizontalPadding)
        .frame(maxWidth: .infinity)
        .frame(height: layout.rowHeight)
        .background(fill, in: RoundedRectangle(cornerRadius: Metrics.rowCornerRadius))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(accessibilityText)
    }

    /// "Closed · since 9:50 AM" where it fits, else "Closed · 9:50 AM", else "Closed".
    private var status: some View {
        ViewThatFits(in: .horizontal) {
            ForEach(statusLines, id: \.self) { line in
                Text(line)
                    .font(HearthFont.caption.font(fixedSize: layout.statusSize).weight(.semibold))
                    .foregroundStyle(statusColor).lineLimit(1)
            }
        }
    }
}

/// The trailing pill of a compact door row (Unlock / Lock / Open / Close / Stop / Settings).
struct AlarmCompactDoorLabel: View {
    let text: String
    let ink: Color
    let fill: Color
    let layout: AlarmDoorRowsLayout

    private typealias Metrics = AlarmDoorRowsMetrics

    var body: some View {
        Text(text)
            .font(HearthFont.groupLabel.font(fixedSize: layout.buttonTextSize).weight(.semibold))
            .lineLimit(1).foregroundStyle(ink)
            .padding(.horizontal, Metrics.buttonHorizontalPadding)
            .frame(minWidth: layout.buttonMinimumWidth)
            .frame(height: layout.buttonHeight)
            .background(fill, in: RoundedRectangle(cornerRadius: Metrics.buttonCornerRadius))
            .fixedSize(horizontal: true, vertical: false)
    }
}
