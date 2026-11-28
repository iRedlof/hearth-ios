import Foundation

private enum ActivityPanelCopy {
    static let icon = "clock.arrow.circlepath"
    static let quiet = "Quiet"
    static let quietDetail = "No recent events"
    static let choose = "Choose events"
    static let empty = "No recent activity"
    static let nothingElse = "Nothing else recent"
}

/// One earlier event in the body: when, its glyph, and what happened.
public struct ActivityPanelRow: Sendable, Equatable, Identifiable {
    public let id: String
    public let time: String
    /// SF Symbol name.
    public let icon: String
    public let text: String
}

/// Everything the Activity widget draws.
public struct ActivityPanel: Sendable, Equatable {
    public let rail: PanelRail
    public let prompt: PanelPrompt?
    public let notice: String?
    /// The events before the latest, newest first; the view pages them (`panelPage`).
    public let rows: [ActivityPanelRow]
    /// Shown instead of rows when the latest event is the only one.
    public let note: String?
    public let checked: String?
}

/// The glyph for a kind of event.
public func activityIcon(_ kind: ActivityKind) -> String {
    switch kind {
    case .alarm: "shield.fill"
    case .lock: "lock.fill"
    case .carLock: "car.fill"
    case .garage: "door.garage.closed"
    case .door: "door.left.hand.closed"
    case .charge: "bolt.fill"
    }
}

/// The Activity widget: the latest event of the last 24 hours on the rail (what, then when), the
/// events before it in the body. It only informs, so its rail is always neutral.
public func activityPanel(_ snap: ActivitySnapshot, now: Date, zone: TimeZone = .current,
                          locale: Locale = .current) -> ActivityPanel {
    let items = activityInWindow(snap.items, now: now)
    let time: (ActivityItem) -> String = { activityTimeLabel($0.at, now: now, zone: zone, locale: locale) }
    let prompt = panelPrompt(state: snap.state, error: snap.error, hasItems: !items.isEmpty,
                             choice: ActivityPanelCopy.choose, empty: ActivityPanelCopy.empty)
    let rows = items.dropFirst().enumerated().map { index, item in
        ActivityPanelRow(id: "\(index)|\(item.eventKey)", time: time(item), icon: activityIcon(item.kind),
                         text: activityRowText(item))
    }
    return ActivityPanel(rail: activityRail(snap.state, latest: items.first, time: time), prompt: prompt,
                         notice: panelNotice(error: snap.error, prompt: prompt), rows: rows,
                         note: prompt == nil && rows.isEmpty ? ActivityPanelCopy.nothingElse : nil,
                         checked: panelCheckedTime(snap.checkedAt))
}

private func activityRowText(_ item: ActivityItem) -> String {
    let parts = activityDisplayParts(item)
    return [parts.name, parts.action].filter { !$0.isEmpty }.joined(separator: " ")
}

private func activityRail(_ state: TileSnapshotState, latest: ActivityItem?,
                          time: (ActivityItem) -> String) -> PanelRail {
    let icon = ActivityPanelCopy.icon
    switch state {
    case .setup:
        return panelSetupRail(icon: icon)
    case .loading:
        return panelCheckingRail(icon: icon)
    case .failed, .ready, .empty, .choose:
        guard let latest else {
            return state == .failed
                ? PanelRail(icon: icon, word: PanelCopy.cantRead, detail: PanelCopy.homeUnreachable, tone: PanelTone.neutral)
                : PanelRail(icon: icon, word: ActivityPanelCopy.quiet, detail: ActivityPanelCopy.quietDetail,
                            tone: PanelTone.neutral)
        }
        let parts = activityDisplayParts(latest)
        return PanelRail(icon: activityIcon(latest.kind), word: parts.name,
                         detail: [parts.action, time(latest)].filter { !$0.isEmpty }.joined(separator: "\n"),
                         tone: PanelTone.neutral)
    }
}
