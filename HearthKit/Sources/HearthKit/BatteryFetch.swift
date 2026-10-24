import Foundation

/// The Battery widget's display payload: the summary + when it was read.
public struct BatterySnapshot: Sendable, Equatable {
    public let summary: BatterySummary
    public let checkedAt: String
    public init(summary: BatterySummary, checkedAt: String) { self.summary = summary; self.checkedAt = checkedAt }

    public static let sample = BatterySnapshot(summary: batterySummary([
        Battery(id: "a", name: "Front Door Lock", level: 9),
        Battery(id: "b", name: "Backyard Motion", level: 24),
        Battery(id: "c", name: "Living Room Remote", level: 61),
        Battery(id: "d", name: "Garage Sensor", level: 88),
        Battery(id: "e", name: "Office Thermometer", level: 95),
    ]), checkedAt: "9:41 AM")
}

/// Live batteries via `BATTERY_TEMPLATE` (auto-discovered — no config). Returns `.sample` when not
/// connected; a reachable-but-failed read shows an honest "Can't reach HA" card.
public func fetchBatterySnapshot(_ config: HaConfig, now: Date = Date()) async -> BatterySnapshot {
    let checked = widgetClock(now)
    guard config.baseUrl.hasPrefix("https://"), config.hasAuth else { return .sample }
    do {
        let json = try await HaClient(config).template(BATTERY_TEMPLATE)
        return BatterySnapshot(summary: batterySummary(batteriesFromTemplate(json)), checkedAt: checked)
    } catch {
        return BatterySnapshot(summary: BatterySummary(headline: "Can't reach HA", tone: .unknown,
                                                       detail: friendlyError(error), rows: []), checkedAt: checked)
    }
}

/// "9:41 AM" — shared short clock for the non-Beacon widget "Checked" stamps.
func widgetClock(_ date: Date) -> String {
    let f = DateFormatter(); f.dateFormat = "h:mm a"; return f.string(from: date)
}
