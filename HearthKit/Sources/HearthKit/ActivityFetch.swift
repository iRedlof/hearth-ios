import Foundation

/// The Activity widget's payload: recent events + when it was read.
public struct ActivitySnapshot: Sendable, Equatable {
    public let items: [ActivityItem]; public let checkedAt: String
    public init(items: [ActivityItem], checkedAt: String) { self.items = items; self.checkedAt = checkedAt }

    public static let sample = ActivitySnapshot(items: [
        ActivityItem(at: Date().addingTimeInterval(-300), kind: .garage, text: "Garage closed", by: "Arriving home routine"),
        ActivityItem(at: Date().addingTimeInterval(-1800), kind: .alarm, text: "Home Alarm disarmed", by: nil),
        ActivityItem(at: Date().addingTimeInterval(-3600), kind: .lock, text: "Front Door unlocked", by: nil),
        ActivityItem(at: Date().addingTimeInterval(-6300), kind: .door, text: "Back Door opened", by: nil),
        ActivityItem(at: Date().addingTimeInterval(-9000), kind: .charge, text: "Tesla plugged in", by: nil),
    ], checkedAt: "9:41 AM")
}

/// Last 24h of alarm / lock / door events from Home Assistant's logbook. Mirrors Android
/// `ActivityRepository`. (Car lock/charge integration is a documented follow-up.)
public func fetchActivitySnapshot(_ config: HaConfig, now: Date = Date()) async -> ActivitySnapshot {
    let checked = widgetClock(now)
    let ids = ([config.entityId, config.lockId] + config.doorIds).filter { !$0.isEmpty }
    guard config.baseUrl.hasPrefix("https://"), config.hasAuth, !ids.isEmpty else { return .sample }
    do {
        let log = try await HaClient(config).logbookJson(since: now.addingTimeInterval(-24 * 3600), ids: ids)
        return ActivitySnapshot(items: activityFrom(log, names: namesFromLogbook(log), haStart: nil), checkedAt: checked)
    } catch {
        return ActivitySnapshot(items: [], checkedAt: checked)
    }
}

/// `{entity_id: name}` harvested from the logbook entries (HA includes each entity's friendly name).
private func namesFromLogbook(_ json: String) -> [String: String] {
    guard let data = json.data(using: .utf8),
          let arr = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]] else { return [:] }
    var names: [String: String] = [:]
    for e in arr where (e["name"] as? String)?.isEmpty == false {
        if let id = e["entity_id"] as? String { names[id] = e["name"] as? String }
    }
    return names
}
