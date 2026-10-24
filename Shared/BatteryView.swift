import SwiftUI
import AppIntents
import HearthKit

/// The Batteries card (read-only, `.systemLarge`): a tone-coloured panel with "N low" + a line, and
/// every battery lowest-first with a level bar. Ported from the Android Batteries widget.
public struct BatteryView: View {
    public let snap: BatterySnapshot
    public init(_ snap: BatterySnapshot) { self.snap = snap }

    private var tone: DoorsTone { snap.summary.tone }
    private var fill: Color { Color(argb: tone.fillARGB) }
    private var ink: Color { Color(argb: tone.inkARGB) }

    public var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            header
            if let detail = snap.summary.detail {
                Text(detail).font(.system(size: 11)).foregroundStyle(ink.opacity(0.8)).lineLimit(1).minimumScaleFactor(0.8)
            }
            Rectangle().fill(ink.opacity(0.18)).frame(height: 1).padding(.vertical, 1)
            ForEach(snap.summary.rows.prefix(8), id: \.name) { rowView($0) }
            Spacer(minLength: 0)
        }
        .padding(15)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(LinearGradient(colors: [fill, fill.opacity(0.9)], startPoint: .topLeading, endPoint: .bottomTrailing))
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            VStack(alignment: .leading, spacing: 0) {
                Text("Batteries").font(.system(size: 12, weight: .semibold)).foregroundStyle(ink.opacity(0.7))
                Text(snap.summary.headline).font(.system(size: 25, weight: .heavy)).tracking(-0.5).foregroundStyle(ink)
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
            Spacer(minLength: 2)
            Button(intent: WidgetRefreshIntent("com.rohit.hearth.battery")) {
                Image(systemName: "arrow.clockwise").font(.system(size: 12, weight: .semibold)).foregroundStyle(ink.opacity(0.7))
            }.buttonStyle(.plain)
            VStack(alignment: .trailing, spacing: -1) {
                Text("Checked").font(.system(size: 9)); Text(snap.checkedAt).font(.system(size: 9))
            }.foregroundStyle(ink.opacity(0.7)).invalidatableContent()
        }
    }

    private func rowView(_ row: BatteryRow) -> some View {
        let barColor: Color = row.empty ? Color(argb: 0xFFB3261E) : (row.low ? Color(argb: 0xFF9A6B00) : ink.opacity(0.5))
        return HStack(spacing: 8) {
            Text(row.name).font(.system(size: 13, weight: row.low ? .semibold : .regular)).foregroundStyle(ink)
                .lineLimit(1).minimumScaleFactor(0.8)
            Spacer(minLength: 6)
            ZStack(alignment: .leading) {
                Capsule().fill(ink.opacity(0.15)).frame(width: 64, height: 5)
                Capsule().fill(barColor).frame(width: 64 * CGFloat(row.level) / 100, height: 5)
            }
            Text("\(row.level)%").font(.system(size: 13, weight: .bold))
                .foregroundStyle(row.low ? barColor : ink).frame(width: 40, alignment: .trailing)
        }
        .padding(.vertical, 1.5)
    }
}
