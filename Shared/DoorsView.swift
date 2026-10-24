import SwiftUI
import AppIntents
import HearthKit

/// The Doors card (`.systemLarge`): a tone-coloured panel (green all shut, amber something open, red
/// open ≥30 min) listing doors open-first with their status and action — Close/Stop/Lock in place,
/// garage **Open** through the Face ID gate. Ported from the Android Doors widget.
public struct DoorsView: View {
    public let snap: DoorsSnapshot
    public init(_ snap: DoorsSnapshot) { self.snap = snap }

    private var tone: DoorsTone { snap.summary.tone }
    private var fill: Color { Color(argb: tone.fillARGB) }
    private var ink: Color { Color(argb: tone.inkARGB) }

    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            header
            if let lockLine = snap.summary.lockLine {
                Text(lockLine).font(.system(size: 11)).foregroundStyle(ink.opacity(0.75)).lineLimit(1)
            }
            Rectangle().fill(ink.opacity(0.18)).frame(height: 1).padding(.vertical, 1)
            ForEach(snap.summary.rows.prefix(6), id: \.id) { row($0) }
            Spacer(minLength: 0)
        }
        .padding(15)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(LinearGradient(colors: [fill, fill.opacity(0.9)], startPoint: .topLeading, endPoint: .bottomTrailing))
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(snap.summary.headline).font(.system(size: 22, weight: .heavy)).tracking(-0.5)
                .foregroundStyle(ink).lineLimit(1).minimumScaleFactor(0.7)
            Spacer(minLength: 2)
            Button(intent: WidgetRefreshIntent("com.rohit.hearth.doors")) {
                Image(systemName: "arrow.clockwise").font(.system(size: 12, weight: .semibold)).foregroundStyle(ink.opacity(0.7))
            }.buttonStyle(.plain)
            Text(snap.checkedAt).font(.system(size: 10)).foregroundStyle(ink.opacity(0.7))
        }
    }

    private func row(_ v: DoorView) -> some View {
        HStack(spacing: 9) {
            Image(systemName: icon(v)).font(.system(size: 15)).foregroundStyle(ink.opacity(0.85)).frame(width: 20)
            VStack(alignment: .leading, spacing: 0) {
                Text(v.name).font(.system(size: 13.5, weight: .medium)).foregroundStyle(ink).lineLimit(1)
                Text(v.status).font(.system(size: 10.5)).foregroundStyle(ink.opacity(0.7)).lineLimit(1).minimumScaleFactor(0.8)
            }
            Spacer(minLength: 4)
            if let action = v.action { actionButton(v.id, action) }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder private func actionButton(_ id: String, _ action: DoorAction) -> some View {
        let label = Text(action.label).font(.system(size: 12, weight: .semibold)).foregroundStyle(ink)
            .padding(.horizontal, 12).frame(height: 30)
            .background(ink.opacity(0.14), in: Capsule())
        if action.needsConfirm {   // garage Open → Face ID gate
            Button(intent: DoorOpenIntent(id)) { label }.buttonStyle(.plain)
        } else {
            Button(intent: DoorActionIntent(id, action)) { label }.buttonStyle(.plain)
        }
    }

    private func icon(_ v: DoorView) -> String {
        let open = v.open ?? false
        if v.id.hasPrefix("lock.") { return open ? "lock.open.fill" : "lock.fill" }
        if v.id.hasPrefix("cover.") { return open ? "door.garage.open" : "door.garage.closed" }
        return open ? "door.left.hand.open" : "door.left.hand.closed"
    }
}
