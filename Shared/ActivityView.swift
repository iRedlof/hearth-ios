import SwiftUI
import AppIntents
import HearthKit

/// The Activity card (read-only, `.systemLarge`): a neutral panel listing recent home events newest
/// first — time, kind icon, what happened, and (if an automation did it) who. Ported from the Android
/// Activity widget.
public struct ActivityView: View {
    public let snap: ActivitySnapshot
    private let referenceNow: Date?
    @ScaledMetric(relativeTo: .body) private var textScale: CGFloat = 1
    public init(_ snap: ActivitySnapshot, now: Date? = nil) { self.snap = snap; self.referenceNow = now }

    private var fill: Color { Color(argb: DoorsTone.unknown.fillARGB) }
    private var ink: Color { Color(argb: DoorsTone.unknown.inkARGB) }

    public var body: some View {
        GeometryReader { geometry in
            content(width: geometry.size.width, height: geometry.size.height, now: referenceNow ?? Date())
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(LinearGradient(colors: [fill, fill.opacity(0.92)], startPoint: .topLeading, endPoint: .bottomTrailing))
    }

    private func content(width: CGFloat, height: CGFloat, now: Date) -> some View {
        let items = activityInWindow(snap.items, now: now)
        let headline = activitySnapshotHeadline(snap, now: now)
        let checked = snap.checkedAt.isEmpty ? nil :
            "\(snap.error != nil ? "Last checked" : "Checked") \(snap.checkedAt)"
        let layout = activityLayout(width: Double(width), height: Double(height), fontScale: Double(textScale),
                                    items: items, hasError: snap.error != nil, now: now, headline: headline, checkedText: checked)
        return VStack(alignment: .leading, spacing: 0) {
            if layout.summaryOnly {
                if layout.showSummaryTitle {
                    HStack(spacing: 8) {
                        Text(snap.error != nil ? "Unavailable" : "Activity").font(.system(size: 13 * textScale, weight: .bold))
                            .foregroundStyle(ink).lineLimit(layout.headlineLines).frame(maxWidth: .infinity, alignment: .leading)
                        refreshButton
                    }
                    Spacer().frame(height: 4)
                }
                Button(intent: WidgetRefreshIntent("com.rohit.hearth.activity")) {
                    Text(layout.summaryLabel).font(.system(size: 13 * textScale, weight: .medium)).foregroundStyle(ink)
                        .lineLimit(layout.countLines).frame(maxWidth: .infinity, alignment: .leading)
                }.buttonStyle(.plain)
                if let stamp = layout.checkedText, layout.checkedLines > 0 {
                    Spacer().frame(height: 2)
                    Text(stamp).font(.system(size: 11 * textScale)).foregroundStyle(ink.opacity(0.65)).lineLimit(layout.checkedLines)
                }
            } else {
                header(headline: headline, layout: layout)
                if let error = snap.error {
                    Spacer().frame(height: 4)
                    Text(error).font(.system(size: 11 * textScale)).foregroundStyle(ink.opacity(0.7)).lineLimit(1)
                }
                if let stamp = layout.checkedText, layout.checkedLines > 0 {
                    Spacer().frame(height: 2)
                    Text(stamp).font(.system(size: 11 * textScale)).foregroundStyle(ink.opacity(0.65)).lineLimit(layout.checkedLines)
                }
                Spacer().frame(height: 8)
                VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(layout.rows.enumerated()), id: \.offset) { row($0.element, layout: layout, now: now) }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                if layout.hiddenCount > 0 {
                    Text("+\(layout.hiddenCount) more \(layout.hiddenCount == 1 ? "event" : "events")")
                        .font(.system(size: 11 * textScale)).foregroundStyle(ink.opacity(0.65)).lineLimit(layout.countLines)
                }
            }
        }
        .padding(layout.padding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: layout.summaryOnly ? .center : .topLeading)
    }

    private func header(headline: String, layout: ActivityLayout) -> some View {
        HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Text("Activity · last 24 hours").font(.system(size: 12 * textScale, weight: .medium)).foregroundStyle(ink.opacity(0.7))
                        .lineLimit(1)
                }
                Text(headline).font(.system(size: 19 * textScale, weight: .bold))
                    .foregroundStyle(ink).lineLimit(layout.headlineLines)
            }.frame(maxWidth: .infinity, alignment: .leading)
            refreshButton
        }
    }

    private var refreshButton: some View {
        Button(intent: WidgetRefreshIntent("com.rohit.hearth.activity")) {
            Image(systemName: "arrow.clockwise").font(.system(size: 12, weight: .semibold)).foregroundStyle(ink.opacity(0.7))
                .frame(width: 36, height: 36)
        }.buttonStyle(.plain)
    }

    private func row(_ row: ActivityRowLayout, layout: ActivityLayout, now: Date) -> some View {
        let item = row.item
        let parts = activityDisplayParts(item)
        return HStack(alignment: .top, spacing: 8) {
            if layout.rowMode == .inline {
                Text(activityTimeLabel(item.at, now: now)).font(.system(size: 11 * textScale, weight: .medium))
                    .foregroundStyle(ink.opacity(0.65)).lineLimit(1).frame(width: layout.timeWidth, alignment: .leading)
            }
            Image(systemName: icon(item.kind)).font(.system(size: 12)).foregroundStyle(ink.opacity(0.8)).frame(width: 16)
            VStack(alignment: .leading, spacing: 0) {
                if layout.rowMode == .stacked {
                    Text(parts.name).font(.system(size: 13 * textScale, weight: .medium)).foregroundStyle(ink)
                        .lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                    Text(parts.action).font(.system(size: 13 * textScale, weight: .medium)).foregroundStyle(ink)
                        .lineLimit(row.actionLines).frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    HStack(spacing: 5) {
                        Text(parts.name).font(.system(size: 13 * textScale, weight: .medium)).foregroundStyle(ink)
                            .lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                        Text(parts.action).font(.system(size: 13 * textScale, weight: .medium)).foregroundStyle(ink)
                            .lineLimit(1).frame(width: layout.actionWidth, alignment: .leading)
                    }
                }
                if row.timeLines > 0 {
                    Text(activityTimeLabel(item.at, now: now)).font(.system(size: 11 * textScale)).foregroundStyle(ink.opacity(0.6))
                        .lineLimit(row.timeLines)
                }
                if let by = item.by {
                    Text("by \(by)").font(.system(size: 11 * textScale)).foregroundStyle(ink.opacity(0.6)).lineLimit(1)
                }
            }
        }.padding(.vertical, 2).frame(height: row.height, alignment: .topLeading)
    }

    private func icon(_ kind: ActivityKind) -> String {
        switch kind {
        case .alarm: "shield.fill"
        case .lock: "lock.fill"
        case .carLock: "car.fill"
        case .garage: "door.garage.closed"
        case .door: "door.left.hand.closed"
        case .charge: "bolt.fill"
        }
    }
}
