import Foundation

private enum BatteryPanelCopy {
    static let setupIcon = "minus.plus.batteryblock.fill"
    static let goodIcon = "battery.100"
    static let lowIcon = "battery.25"
    static let none = "No batteries"
    static let noReading = "No reading"
    static let choose = "Choose batteries"
    static let empty = "No batteries found"
}

/// How a battery's reading is coloured in its row.
public enum BatteryReadingTone: Sendable, Equatable {
    case normal, low, empty, unavailable
}

/// One battery in the body: its name and its level.
public struct BatteryPanelRow: Sendable, Equatable, Identifiable {
    public let id: String
    public let name: String
    public let reading: String
    public let tone: BatteryReadingTone
    /// A low battery's name is drawn heavier.
    public let emphasised: Bool
}

/// Everything the Batteries widget draws.
public struct BatteryPanel: Sendable, Equatable {
    public let rail: PanelRail
    public let prompt: PanelPrompt?
    public let notice: String?
    /// Every battery, lowest first; the view pages them (`panelPage`).
    public let rows: [BatteryPanelRow]
    public let checked: String?
}

/// The Batteries widget: "All good" (green) or "2 low" (amber) on the rail, the lowest batteries
/// in the body. Unreachable keeps the last-known answer on a neutral rail.
public func batteryPanel(_ snap: BatterySnapshot) -> BatteryPanel {
    let rows = snap.summary.rows.map(batteryPanelRow)
    let prompt = panelPrompt(state: snap.state, error: snap.error, hasItems: !rows.isEmpty,
                             choice: BatteryPanelCopy.choose, empty: BatteryPanelCopy.empty)
    return BatteryPanel(rail: batteryRail(snap), prompt: prompt,
                        notice: panelNotice(error: snap.error, prompt: prompt), rows: rows,
                        checked: panelCheckedTime(snap.checkedAt))
}

private func batteryPanelRow(_ row: BatteryRow) -> BatteryPanelRow {
    let tone: BatteryReadingTone = !row.available ? .unavailable : row.empty ? .empty : row.low ? .low : .normal
    return BatteryPanelRow(id: row.id, name: row.name, reading: row.readingLabel, tone: tone, emphasised: row.low)
}

private func batteryRail(_ snap: BatterySnapshot) -> PanelRail {
    let rows = snap.summary.rows
    let anyLow = rows.contains(where: \.low)
    let icon = anyLow ? BatteryPanelCopy.lowIcon : BatteryPanelCopy.goodIcon
    switch snap.state {
    case .setup:
        return panelSetupRail(icon: BatteryPanelCopy.setupIcon)
    case .loading:
        return panelCheckingRail(icon: BatteryPanelCopy.goodIcon)
    case .failed:
        guard !rows.isEmpty else {
            return PanelRail(icon: BatteryPanelCopy.lowIcon, word: BatteryPanelCopy.noReading,
                             detail: PanelCopy.homeUnreachable, tone: PanelTone.neutral)
        }
        return PanelRail(icon: icon, word: snap.summary.headline, detail: batteryRailDetail(snap.summary),
                         tone: PanelTone.neutral)
    case .ready, .empty, .choose:
        guard !rows.isEmpty else {
            return PanelRail(icon: BatteryPanelCopy.goodIcon, word: BatteryPanelCopy.none, detail: "",
                             tone: PanelTone.neutral)
        }
        return PanelRail(icon: icon, word: snap.summary.headline, detail: batteryRailDetail(snap.summary),
                         tone: batteryRailTone(snap.summary.tone))
    }
}

/// What is low, by name; otherwise how many batteries are tracked.
private func batteryRailDetail(_ summary: BatterySummary) -> String {
    if summary.rows.contains(where: \.low), let detail = summary.detail { return detail }
    return "\(summary.rows.count) tracked"
}

/// Green "All good", amber "N low". A nearly empty battery is red in its own row; the rail keeps
/// to the three two-panel tones.
private func batteryRailTone(_ tone: DoorsTone) -> DoorsTone {
    switch tone {
    case .calm: PanelTone.settled
    case .warn, .alert: PanelTone.active
    case .unknown: PanelTone.neutral
    }
}
