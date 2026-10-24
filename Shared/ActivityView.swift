import SwiftUI
import AppIntents
import HearthKit

/// The Activity card (read-only, `.systemLarge`): a neutral panel listing recent home events newest
/// first — time, kind icon, what happened, and (if an automation did it) who. Ported from the Android
/// Activity widget.
public struct ActivityView: View {
    public let snap: ActivitySnapshot
    public init(_ snap: ActivitySnapshot) { self.snap = snap }

    private var fill: Color { Color(argb: DoorsTone.unknown.fillARGB) }
    private var ink: Color { Color(argb: DoorsTone.unknown.inkARGB) }

    public var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            header
            Rectangle().fill(ink.opacity(0.18)).frame(height: 1)
            if snap.items.isEmpty {
                Text("Nothing recent").font(.system(size: 13)).foregroundStyle(ink.opacity(0.7)).padding(.top, 4)
            }
            ForEach(Array(snap.items.prefix(7).enumerated()), id: \.offset) { row($0.element) }
            Spacer(minLength: 0)
        }
        .padding(15)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(LinearGradient(colors: [fill, fill.opacity(0.92)], startPoint: .topLeading, endPoint: .bottomTrailing))
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Activity").font(.system(size: 18, weight: .bold)).foregroundStyle(ink)
            Spacer()
            Button(intent: WidgetRefreshIntent("com.rohit.hearth.activity")) {
                Image(systemName: "arrow.clockwise").font(.system(size: 12, weight: .semibold)).foregroundStyle(ink.opacity(0.7))
            }.buttonStyle(.plain)
            Text(snap.checkedAt).font(.system(size: 10)).foregroundStyle(ink.opacity(0.7)).padding(.leading, 6)
        }
    }

    private func row(_ item: ActivityItem) -> some View {
        HStack(alignment: .top, spacing: 9) {
            Text(timeStr(item.at)).font(.system(size: 11, weight: .medium)).foregroundStyle(ink.opacity(0.65))
                .frame(width: 56, alignment: .leading)
            Image(systemName: icon(item.kind)).font(.system(size: 12)).foregroundStyle(ink.opacity(0.8)).frame(width: 16)
            VStack(alignment: .leading, spacing: 0) {
                Text(item.text).font(.system(size: 13, weight: .medium)).foregroundStyle(ink).lineLimit(1).minimumScaleFactor(0.8)
                if let by = item.by { Text(by).font(.system(size: 10.5)).foregroundStyle(ink.opacity(0.6)).lineLimit(1) }
            }
            Spacer(minLength: 0)
        }.padding(.vertical, 1.5)
    }

    private func icon(_ kind: ActivityKind) -> String {
        switch kind {
        case .alarm: "shield.fill"
        case .lock, .carLock: "lock.fill"
        case .garage: "door.garage.closed"
        case .door: "door.left.hand.closed"
        case .charge: "bolt.fill"
        }
    }

    private func timeStr(_ date: Date) -> String { let f = DateFormatter(); f.dateFormat = "h:mm a"; return f.string(from: date) }
}
