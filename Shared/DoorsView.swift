import SwiftUI
import AppIntents
import HearthKit

/// The Doors card (`.systemLarge`): a tone-coloured panel (green all shut, amber something open, red
/// open ≥30 min) listing doors open-first with direct garage and lock actions.
public struct DoorsView: View {
    public let snap: DoorsSnapshot
    @ScaledMetric(relativeTo: .body) private var scaledNameSize: CGFloat = 14
    @ScaledMetric(relativeTo: .body) private var scaledSecondarySize: CGFloat = 12
    @ScaledMetric(relativeTo: .title2) private var scaledHeadlineSize: CGFloat = 22
    public init(_ snap: DoorsSnapshot) { self.snap = snap }

    private var presentation: DoorsSummary { doorsCommandPresentation(snap.summary, operation: snap.operation) }
    private var tone: DoorsTone { presentation.tone }
    private var fill: Color { Color(argb: tone.fillARGB) }
    private var ink: Color { Color(argb: tone.inkARGB) }
    private var nameSize: CGFloat { max(14, scaledNameSize) }
    private var secondarySize: CGFloat { max(12, scaledSecondarySize) }
    private var fontScale: CGFloat { nameSize / 14 }

    public var body: some View {
        GeometryReader { geometry in
            let identityWidth = max(0, geometry.size.width - 30 - 20 - 20 - 9 - (5 * nameSize + 24) - 8)
            let identities = doorRowIdentities(snap.summary.rows, nameCapacity: Int(identityWidth / nameSize),
                detailCapacity: Int(identityWidth / (secondarySize * 0.62)))
            let priorityID = snap.summary.rows.first { identities[$0.id]?.identifiable == true && rowAction($0) == .stop }?.id
            let layout = doorsCollectionLayout(width: Double(geometry.size.width), height: Double(geometry.size.height),
                fontScale: Double(fontScale), rows: snap.summary.rows, hasError: snap.error != nil, priorityID: priorityID)
            let budget = layout.budget
            let rows = Array(snap.summary.rows.prefix(budget.count))
            Group {
                if let priorityID = layout.priorityID, let priority = snap.summary.rows.first(where: { $0.id == priorityID }) {
                    VStack(alignment: .leading, spacing: 0) {
                        row(priority, height: CGFloat(budget.rowHeight), identity: identities[priorityID])
                        if !layout.lines.isEmpty {
                            Spacer().frame(height: 4)
                            VStack(alignment: .leading, spacing: 0) {
                                ForEach(Array(layout.lines.enumerated()), id: \.offset) { _, line in
                                    Text(line).font(.system(size: CGFloat(layout.fontSize), design: .monospaced))
                                        .foregroundStyle(ink.opacity(0.75)).lineLimit(1)
                                        .frame(height: CGFloat(layout.lineHeight), alignment: .leading)
                                }
                            }
                        }
                    }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                } else if budget.summaryOnly {
                    Button(intent: WidgetRefreshIntent("com.rohit.hearth.doors")) {
                        VStack(spacing: 4) {
                            ForEach(Array(layout.lines.enumerated()), id: \.offset) { _, line in
                                Text(line).font(.system(size: CGFloat(layout.fontSize), design: .monospaced))
                                    .foregroundStyle(ink).lineLimit(1).frame(height: CGFloat(layout.lineHeight))
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                    }.buttonStyle(.plain)
                } else {
                    VStack(alignment: .leading, spacing: 0) {
                        header
                        if let error = snap.error {
                            Text(error).font(.system(size: secondarySize)).foregroundStyle(ink.opacity(0.8))
                                .lineLimit(2).frame(height: 32 * fontScale, alignment: .leading)
                        }
                        Spacer().frame(height: 8)
                        VStack(spacing: 6) {
                            ForEach(rows, id: \.id) { value in
                                row(value, height: CGFloat(budget.rowHeight), identity: identities[value.id])
                            }
                            if snap.summary.rows.isEmpty {
                                Text(emptyMessage).font(.system(size: nameSize)).foregroundStyle(ink.opacity(0.75))
                                    .multilineTextAlignment(.center)
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                        if budget.showOverflow {
                            Spacer().frame(height: 4)
                            VStack(alignment: .leading, spacing: 0) {
                                ForEach(Array(layout.lines.enumerated()), id: \.offset) { _, line in
                                    Text(line).font(.system(size: CGFloat(layout.fontSize), design: .monospaced))
                                        .foregroundStyle(ink.opacity(0.75)).lineLimit(1)
                                        .frame(height: CGFloat(layout.lineHeight), alignment: .leading)
                                }
                            }
                        }
                    }
                }
            }
            .padding(CGFloat(budget.padding))
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .background(LinearGradient(colors: [fill, fill.opacity(0.9)], startPoint: .topLeading, endPoint: .bottomTrailing))
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Doors").font(.system(size: secondarySize, weight: .medium)).foregroundStyle(ink.opacity(0.7))
                Text(headline).font(.system(size: max(22, scaledHeadlineSize), weight: .heavy))
                    .foregroundStyle(ink).lineLimit(1)
            }
            Spacer(minLength: 2)
            if !snap.checkedAt.isEmpty {
                VStack(alignment: .trailing, spacing: 0) {
                    Text(snap.error == nil ? "Checked" : "Last checked")
                    Text(snap.checkedAt).invalidatableContent()
                }.font(.system(size: secondarySize)).foregroundStyle(ink.opacity(0.7))
            }
            Button(intent: WidgetRefreshIntent("com.rohit.hearth.doors")) {
                Image(systemName: "arrow.clockwise").font(.system(size: nameSize, weight: .semibold))
                    .foregroundStyle(ink.opacity(0.7)).frame(width: 34, height: 34)
            }.buttonStyle(.plain)
        }
        .frame(height: 52 * fontScale, alignment: .center)
    }

    private var headline: String {
        switch snap.state {
        case .setup: "Set up Home Assistant"
        case .choose: "Choose doors"
        case .loading: "Loading doors…"
        case .failed: snap.summary.rows.isEmpty ? "Can't read doors" : presentation.headline
        default: presentation.headline
        }
    }

    private var emptyMessage: String {
        switch snap.state {
        case .setup: "Connect Home Assistant in Hearth"
        case .choose: "Choose doors in Hearth"
        case .loading: "Waiting for your doors"
        case .failed: "Refresh to try again"
        default: "No doors chosen"
        }
    }

    private func row(_ v: DoorView, height: CGFloat, identity: DoorRowIdentity?) -> some View {
        HStack(spacing: 9) {
            Image(systemName: icon(v)).font(.system(size: 18)).foregroundStyle(ink.opacity(0.85)).frame(width: 20)
            VStack(alignment: .leading, spacing: 0) {
                Text(v.name).font(.system(size: nameSize, weight: .medium)).foregroundStyle(ink).lineLimit(1)
                Text(identity?.label.map { "\($0) · \(rowStatus(v).components(separatedBy: " ·").first ?? rowStatus(v))" } ?? rowStatus(v))
                    .font(.system(size: secondarySize, design: identity?.label == nil ? .default : .monospaced))
                    .foregroundStyle(ink.opacity(0.7)).lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Spacer(minLength: 4)
            if identity?.identifiable == true, let action = rowAction(v) { actionButton(v.id, action) }
        }
        .padding(.horizontal, 10)
        .frame(height: height)
        .background(ink.opacity(0.07), in: RoundedRectangle(cornerRadius: 16))
    }

    private func rowStatus(_ row: DoorView) -> String {
        guard let operation = snap.operation, operation.pending, operation.entityID == row.id,
              let action = DoorAction(rawValue: operation.action) else { return row.status }
        return action.pending
    }

    private func rowAction(_ row: DoorView) -> DoorAction? {
        if snap.doors.first(where: { $0.id == row.id })?.supportsStop == false,
           row.action == .stop || snap.operation?.pending == true && snap.operation?.entityID == row.id { return nil }
        guard let operation = snap.operation, operation.pending else { return row.action }
        // Stop takes over only this garage's unfinished Open/Close; other taps remain inert.
        guard operation.entityID == row.id, row.id.hasPrefix("cover."),
              ["open", "close"].contains(operation.action) else { return nil }
        return .stop
    }

    private func actionButton(_ id: String, _ action: DoorAction) -> some View {
        Button(intent: DoorActionIntent(scope: snap.actionScope ?? "", revision: snap.actionRevision ?? "", id: id, action: action,
            replacingOperation: action == .stop && snap.operation?.pending == true ? snap.operation?.id ?? "" : "")) {
            Text(action.label).font(.system(size: nameSize, weight: .semibold)).foregroundStyle(ink)
                .padding(.horizontal, 12).frame(height: 34 * fontScale)
                .background(ink.opacity(0.14), in: Capsule())
        }.buttonStyle(.plain).disabled((snap.actionScope ?? "").isEmpty || (snap.actionRevision ?? "").isEmpty)
    }

    private func icon(_ v: DoorView) -> String {
        let open = v.open ?? false
        if v.id.hasPrefix("lock.") { return open ? "lock.open.fill" : "lock.fill" }
        if v.id.hasPrefix("cover.") { return open ? "door.garage.open" : "door.garage.closed" }
        return open ? "door.left.hand.open" : "door.left.hand.closed"
    }
}
