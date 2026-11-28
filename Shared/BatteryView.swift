import SwiftUI
import WidgetKit
import AppIntents
import HearthKit

/// A readable collection whose rows are bounded by the actual widget height and text scale.
public struct BatteryView: View {
    public let snap: BatterySnapshot
    @Environment(\.widgetFamily) private var family
    private let layoutFamily: WidgetFamily?
    @ScaledMetric(relativeTo: .body) private var scaledRowFont = 13.0
    @ScaledMetric(relativeTo: .caption) private var scaledLabelFont = 12.0
    @ScaledMetric(relativeTo: .title2) private var scaledHeadlineFont = 25.0
    @Environment(\.cardStyle) private var cardStyle
    /// In-app previews specify their layout family; Home Screen widgets use WidgetKit's environment.
    public init(_ snap: BatterySnapshot, layoutFamily: WidgetFamily? = nil) {
        self.snap = snap
        self.layoutFamily = layoutFamily
    }

    private var compact: Bool { (layoutFamily ?? family) == .systemMedium }
    private var tone: DoorsTone { snap.state == .failed ? .unknown : snap.summary.tone }
    /// Status is the tone card; on a colour or black a low battery shows as an accent
    /// (Android `BatteryWidget.kt:91`).
    private var look: CardLook {
        cardLook(cardStyle, warn: tone == .warn || tone == .alert, emergency: false)
    }
    private var textScale: CGFloat { look.textScale }
    // The card's text size rides on the sizes the layout plans with, so rows still fit.
    private var rowFont: CGFloat { scaledRowFont * textScale }
    private var labelFont: CGFloat { scaledLabelFont * textScale }
    private var headlineFont: CGFloat { scaledHeadlineFont * textScale }
    private var fill: Color { Color(argb: tone.fillARGB) }
    private var ink: Color { look.inkColor(status: tone.inkARGB) }
    private var headlineInk: Color { look.statusColours ? ink : Color(argb: look.headline) }
    private var lowInk: Color { look.statusColours ? Color(argb: 0xFF9A6B00) : Color(argb: look.flag) }
    private var emptyInk: Color {
        look.statusColours ? Color(argb: 0xFFB3261E) : HearthColor.red(look.light ? .light : .dark)
    }
    private var headline: String {
        switch snap.state {
        case .setup: "Connect"
        case .choose: "Choose batteries"
        case .loading: "Checking…"
        case .failed: snap.summary.rows.isEmpty ? "No reading" : "Last reading"
        case .ready, .empty: snap.summary.headline
        }
    }

    public var body: some View {
        GeometryReader { geometry in
            let scale = rowFont / 13
            let budget = batteryCollectionBudget(width: geometry.size.width, height: geometry.size.height, fontScale: scale,
                rows: snap.summary.rows, hasError: snap.error != nil, compact: compact)
            let shown = Array(snap.summary.rows.prefix(budget.rows))
            VStack(alignment: .leading, spacing: 0) {
                if budget.headerMode != .none { header(budget) }
                if snap.summary.rows.isEmpty {
                    TileStatusContent(state: snap.state, error: snap.error,
                                      choice: "Choose batteries", empty: "No batteries found", ink: ink)
                } else {
                    Spacer().frame(height: budget.gap)
                    VStack(alignment: .leading, spacing: 0) {
                    ForEach(shown, id: \.id) { row in
                        rowView(row, budget: budget, width: geometry.size.width - 2 * budget.padding)
                    }
                    if budget.showOverflow {
                        ForEach(budget.overflowLines, id: \.self) { line in
                            Text(line).font(.system(size: 12 * scale)).foregroundStyle(ink.opacity(0.8))
                                .lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                                .frame(height: budget.overflowLineHeight, alignment: .leading)
                        }
                    }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                    if budget.showError, let error = snap.error {
                        Text(error).font(.system(size: labelFont)).foregroundStyle(ink.opacity(0.8))
                            .lineLimit(1).frame(height: 6 + 16 * scale, alignment: .bottomLeading)
                    }
                }
            }
            .padding(budget.padding)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .cardBackground(look) {
            LinearGradient(colors: [fill, fill.opacity(0.9)], startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }

    private func header(_ budget: BatteryRowBudget) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            if budget.headerMode == .compact {
                Text(snap.state == .failed ? "Last read" : "Batteries")
                    .font(.system(size: 12 * rowFont / 13, weight: .semibold)).foregroundStyle(ink.opacity(0.7))
                    .lineLimit(1)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                Text("Batteries").font(.system(size: labelFont, weight: .semibold)).foregroundStyle(ink.opacity(0.7))
                Text(headline).font(.system(size: compact ? headlineFont * 0.8 : headlineFont, weight: .heavy))
                    .tracking(-0.5).foregroundStyle(headlineInk).lineLimit(1)
                }
            }
            Spacer(minLength: 2)
            // "Checked …" is small print (Android `BatteryWidget.kt:96`).
            if !snap.checkedAt.isEmpty && budget.headerMode == .full
                && cardShowsCheckedStamp(smallPrint: look.smallPrint) {
                VStack(alignment: .trailing, spacing: 0) {
                    Text(snap.state == .failed ? "Last read" : "Checked")
                    Text(snap.checkedAt)
                }.font(.system(size: labelFont * 0.85)).foregroundStyle(ink.opacity(0.7)).invalidatableContent()
            }
            Button(intent: WidgetRefreshIntent("com.rohit.hearth.battery")) {
                Image(systemName: "arrow.clockwise").font(.system(size: labelFont, weight: .semibold))
                    .foregroundStyle(ink.opacity(0.7))
            }.buttonStyle(.plain)
        }
        .frame(height: budget.headerHeight, alignment: .top)
    }

    private func rowView(_ row: BatteryRow, budget: BatteryRowBudget, width: CGFloat) -> some View {
        let barColor: Color = row.empty ? emptyInk : (row.low ? lowInk : ink.opacity(0.5))
        return HStack(spacing: 8) {
            Text(row.name).font(.system(size: rowFont, weight: row.low ? .semibold : .regular))
                .foregroundStyle(ink).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
            if !compact && width >= 300 * rowFont / 13, let level = row.level {
                ZStack(alignment: .leading) {
                    Capsule().fill(ink.opacity(0.15)).frame(width: 44, height: 5)
                    Capsule().fill(barColor).frame(width: 44 * CGFloat(level) / 100, height: 5)
                }
            }
            Text(row.readingLabel).font(.system(size: rowFont, weight: .bold))
                .foregroundStyle(row.available ? (row.low ? barColor : ink) : ink.opacity(0.7))
                .frame(width: budget.readingWidth, alignment: .trailing).lineLimit(1)
        }
        .frame(height: budget.rowHeight)
    }
}
