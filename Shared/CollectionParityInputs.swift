import Foundation
import HearthKit

/// Inert raw HA replies mirror CollectionFixtures.kt. Native capture mode blocks every action.
enum CollectionParityInputs {
    static let commonStates = ["setup", "loading", "empty", "ready", "unavailable", "failed",
                               "partial_failure", "overflow", "long_names", "history"]
    static let activityStates = commonStates + ["boundary", "legacy_bypass"]
    static let batteryStates = commonStates + ["binary_low", "invalid_numeric"]
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
    private static func activityRaw(_ state: String, observed: Date) -> [[String: Any]] {
        switch state {
        case "empty": return []
        // Unavailable/transient states are a valid quiet logbook, not invented activity events.
        case "unavailable": return [
            event("cover.garage", state: "unavailable", at: observed.addingTimeInterval(-300)),
            event("lock.front", state: "locking", at: observed.addingTimeInterval(-600))]
        case "overflow": return (0..<18).map { (index: Int) -> [String: Any] in
            let eventState: String = index % 2 == 0 ? "closed" : "open"
            let offset: TimeInterval = -300 - Double(index) * 420
            let date: Date = observed.addingTimeInterval(offset)
            let routine: Bool = index % 3 == 0
            return event("cover.garage", state: eventState, at: date, routine: routine)
        }
        case "boundary": return [
            event("cover.garage", state: "closed", at: now),
            event("lock.front", state: "locked", at: now.addingTimeInterval(-86_400)),
            event("binary_sensor.back", state: "on", at: now.addingTimeInterval(-86_401)),
            event("alarm_control_panel.home", state: "armed_home", at: now.addingTimeInterval(1))]
        case "legacy_bypass": return [
            event("alarm_control_panel.home", state: "armed_custom_bypass", at: observed.addingTimeInterval(-300))]
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
        if state == "loading" { return .loading }
        let names = activityNames.mapValues { state == "long_names" ? "Upstairs primary bedroom balcony entrance" : $0 }
        let previous = mapActivitySnapshot(config: base, reply: .success(json(activityRaw("ready", observed: old))),
                                           names: names, now: old)
        let observed = ["failed", "partial_failure", "history"].contains(state) ? old : now
        let reply: Result<String, HaError>
        if state == "failed" { reply = .failure(HaError(unreachable)) }
        else if state == "partial_failure" {
            reply = .success(json([event("cover.garage", state: "closed", at: now), "invalid logbook row"] as [Any]))
        } else { reply = .success(json(activityRaw(state, observed: observed))) }
        let snapshot = mapActivitySnapshot(config: state == "setup" ? nil : base, reply: reply, names: names,
                                            previous: previous, now: observed)
        guard state == "legacy_bypass" else { return snapshot }
        // Exercise the shipped cache decoder after dropping fields absent from old cache records.
        let data = try! JSONEncoder().encode(snapshot.items)
        var cache = try! JSONSerialization.jsonObject(with: data) as! [[String: Any]]
        for index in cache.indices {
            for key in ["entityId", "name", "action", "eventKey"] { cache[index].removeValue(forKey: key) }
        }
        let items = try! JSONDecoder().decode([ActivityItem].self, from: Data(json(cache).utf8))
        return ActivitySnapshot(items: items, checkedAt: snapshot.checkedAt, state: snapshot.state,
                                error: snapshot.error, observedAt: snapshot.observedAt, windowEnd: snapshot.windowEnd)
    }

    private static func batteryRaw(_ state: String) -> String {
        if state == "empty" { return "[]" }
        let count = state == "overflow" ? 16 : 4
        let names = ["Front Door Lock Battery", "Backyard Motion Battery", "Living Room Remote Battery", "Garage Sensor Battery"]
        let rows: [[String: Any]] = (0..<count).map { index in
            let binary = state == "binary_low" && index < 3
            let unavailable = state == "unavailable" || state == "overflow" && index % 4 == 1
            let raw: Any = state == "invalid_numeric" ? ([-1, 101, "NaN", true] as [Any])[index] :
                [9, 24, 61, 88][index % 4]
            var value: [String: Any] = [
                "id": "\(binary ? "binary_sensor" : "sensor").fixture_battery_\(index + 1)",
                "name": state == "long_names" ? "Upstairs primary bedroom balcony entrance sensor Battery" : names[index % 4],
                "kind": binary ? "binary" : "numeric",
                "state": unavailable ? "unavailable" : binary ? ["on", "off", "unknown"][index] : String(describing: raw)]
            if !binary { value["level"] = raw }
            return value
        }
        return json(rows)
    }

    static func batteries(_ state: String) -> BatterySnapshot {
        precondition(batteryStates.contains(state))
        if state == "loading" { return .loading }
        let previous = mapBatterySnapshot(base, reply: .success(batteryRaw("ready")), now: old)
        let observed = ["failed", "partial_failure", "history"].contains(state) ? old : now
        let reply: Result<String, HaError>
        if state == "failed" { reply = .failure(HaError(unreachable)) }
        else if state == "partial_failure" {
            var rows = try! JSONSerialization.jsonObject(with: Data(batteryRaw("ready").utf8)) as! [Any]
            rows.append("invalid battery row")
            reply = .success(json(rows))
        } else { reply = .success(batteryRaw(state)) }
        return mapBatterySnapshot(state == "setup" ? nil : base, reply: reply, previous: previous, now: observed)
    }
}
