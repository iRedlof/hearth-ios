import Foundation
import HearthKit

/// Inert raw HA replies mirror CollectionFixtures.kt. Native capture mode blocks every action.
enum CollectionParityInputs {
    /// Activity fixtures: five events (the latest on the rail), a quiet day, eighteen events
    /// ("+N more"), long names, not set up, and unreachable with the earlier events kept.
    static let activityStates = ["ready", "empty", "overflow", "long_names", "setup", "failed"]
    /// Batteries fixtures: all good (green), one low with one unavailable (amber), sixteen
    /// ("+13 more"), long names, not set up, and unreachable with the last levels kept (two low).
    static let batteryStates = ["good", "low", "overflow", "long_names", "setup", "failed"]
    static let now = ISO8601DateFormatter().date(from: "2026-10-30T17:00:00Z")!
    private static let old = now.addingTimeInterval(-7_200)
    private static let unreachable = "Can't reach Home Assistant"
    private static let base = HaConfig(baseUrl: "https://example.com", token: "inert", entityId: "")

    private static func json(_ value: Any) -> String {
        String(data: try! JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]), encoding: .utf8)!
    }
    private static func iso(_ date: Date) -> String { ISO8601DateFormatter().string(from: date) }

    private static let activityNames = ["cover.garage": "Garage", "alarm_control_panel.home": "Home Alarm",
        "lock.front": "Front Door", "binary_sensor.back": "Back Door", "binary_sensor.tesla_charge_cable": "Tesla"]
    private static func event(_ id: String, state: String, at: Date, routine: Bool = false) -> [String: Any] {
        var value: [String: Any] = ["entity_id": id, "state": state, "when": iso(at)]
        if routine {
            value["context_event_type"] = "automation_triggered"
            value["context_name"] = "[Ring][Armed & Home]: Routine"
        }
        return value
    }
    private static let overflowActivityCount = 18
    private static let longActivityName = "Upstairs primary bedroom balcony entrance"

    private static func activityRaw(_ state: String, observed: Date) -> [[String: Any]] {
        switch state {
        case "empty": return []
        case "overflow": return (0..<overflowActivityCount).map { (index: Int) -> [String: Any] in
            let eventState: String = index % 2 == 0 ? "closed" : "open"
            let offset: TimeInterval = -300 - Double(index) * 420
            return event("cover.garage", state: eventState, at: observed.addingTimeInterval(offset), routine: index % 3 == 0)
        }
        default: return [
            event("cover.garage", state: "closed", at: observed.addingTimeInterval(-300), routine: true),
            event("alarm_control_panel.home", state: "disarmed", at: observed.addingTimeInterval(-1_800)),
            event("lock.front", state: "unlocked", at: observed.addingTimeInterval(-3_600)),
            event("binary_sensor.back", state: "on", at: observed.addingTimeInterval(-6_300)),
            event("binary_sensor.tesla_charge_cable", state: "on", at: observed.addingTimeInterval(-9_000))]
        }
    }

    static func activity(_ state: String) -> ActivitySnapshot {
        precondition(activityStates.contains(state))
        let names = activityNames.mapValues { state == "long_names" ? longActivityName : $0 }
        let previous = mapActivitySnapshot(config: base, reply: .success(json(activityRaw("ready", observed: old))),
                                           names: names, now: old)
        let observed = state == "failed" ? old : now
        let reply: Result<String, HaError> = state == "failed" ? .failure(HaError(unreachable))
            : .success(json(activityRaw(state, observed: observed)))
        return mapActivitySnapshot(config: state == "setup" ? nil : base, reply: reply, names: names,
                                   previous: previous, now: observed)
    }

    private static let batteryNames = ["Front Door Lock Battery", "Backyard Motion Battery",
                                       "Living Room Remote Battery", "Garage Sensor Battery"]
    private static let longBatteryName = "Upstairs primary bedroom balcony entrance sensor Battery"
    private static let goodLevels = [92, 78, 64, 88]
    /// What an unreachable card last knew: two low, one of them nearly empty.
    private static let lastKnownLevels = [9, 24, 61, 88]
    /// "low": the first three report low / OK / nothing, as binary sensors do.
    private static let binaryStates = ["on", "off", "unknown"]
    private static let overflowBatteryCount = 16

    private static func batteryRaw(_ state: String) -> String {
        let count = state == "overflow" ? overflowBatteryCount : batteryNames.count
        let levels = state == "good" ? goodLevels : lastKnownLevels
        let rows: [[String: Any]] = (0..<count).map { index in
            let binary = state == "low" && index < binaryStates.count
            let unavailable = state == "overflow" && index % batteryNames.count == 1
            let level = levels[index % levels.count]
            var value: [String: Any] = [
                "id": "\(binary ? "binary_sensor" : "sensor").fixture_battery_\(index + 1)",
                "name": state == "long_names" ? longBatteryName : batteryNames[index % batteryNames.count],
                "kind": binary ? "binary" : "numeric",
                "state": unavailable ? "unavailable" : binary ? binaryStates[index] : String(level)]
            if !binary { value["level"] = level }
            return value
        }
        return json(rows)
    }

    static func batteries(_ state: String) -> BatterySnapshot {
        precondition(batteryStates.contains(state))
        let previous = mapBatterySnapshot(base, reply: .success(batteryRaw("failed")), now: old)
        let reply: Result<String, HaError> = state == "failed" ? .failure(HaError(unreachable))
            : .success(batteryRaw(state))
        return mapBatterySnapshot(state == "setup" ? nil : base, reply: reply, previous: previous,
                                  now: state == "failed" ? old : now)
    }
}
