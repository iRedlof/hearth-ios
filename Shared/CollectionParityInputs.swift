import Foundation
import HearthKit

/// Inert raw HA replies mirror CollectionFixtures.kt. Native capture mode blocks every action.
enum CollectionParityInputs {
    static let commonStates = ["setup", "loading", "empty", "ready", "unavailable", "failed",
                               "partial_failure", "overflow", "long_names", "history"]
    static let doorsStates = commonStates + ["moving", "failed_history", "opening_pending",
                                            "opening_pending_unavailable", "stop_pending", "lock_pending", "command_failed"]
    static let activityStates = commonStates + ["boundary", "legacy_bypass"]
    static let batteryStates = commonStates + ["binary_low", "invalid_numeric"]
    static let now = ISO8601DateFormatter().date(from: "2026-10-30T17:00:00Z")!
    private static let old = now.addingTimeInterval(-7_200)
    private static let unreachable = "Can't reach Home Assistant"
    private static let commandFailure = "Couldn't confirm · Refresh to check"
    private static let commandOperation = "00000000-0000-4000-8000-000000000041"
    private static let commandStarted = now.addingTimeInterval(-10)
    private static let actionScope = "fixture"
    private static let actionRevision = "fixture"
    private static let base = HaConfig(baseUrl: "https://example.com", token: "inert", entityId: "")

    private static func json(_ value: Any) -> String {
        String(data: try! JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]), encoding: .utf8)!
    }
    private static func iso(_ date: Date) -> String { ISO8601DateFormatter().string(from: date) }

    private static func doorIDs(_ state: String) -> [String] {
        if state == "overflow" { return (1...14).map { "binary_sensor.fixture_door_\($0)" } }
        return ["cover.garage", "lock.front", "binary_sensor.back", "cover.side_gate"]
    }
    private static func doorReplies(_ ids: [String], state: String, observed: Date) -> [String: HaStateReading] {
        Dictionary(uniqueKeysWithValues: ids.enumerated().map { index, id in
            let name = state == "long_names" ? "Upstairs primary bedroom balcony entrance" :
                ["Garage", "Front Door", "Back Door", "Side Gate"][index % 4]
            let value: String
            if state == "unavailable" { value = "unavailable" }
            else if state == "opening_pending_unavailable" && id == "cover.garage" { value = "unavailable" }
            else if state == "stop_pending" && id == "cover.garage" { value = "opening" }
            else if state == "lock_pending" && id == "lock.front" { value = "unlocked" }
            else if state == "moving" && index == 0 { value = "opening" }
            else if state == "moving" && index == 3 { value = "closing" }
            else if id.hasPrefix("lock.") { value = "locked" }
            else if id.hasPrefix("cover.") { value = "closed" }
            else if state == "overflow" && index % 4 == 0 { value = "on" }
            else if state == "overflow" && index % 4 == 1 { value = "unavailable" }
            else { value = "off" }
            var attributes: [String: Any] = ["friendly_name": name]
            if id.hasPrefix("cover.") { attributes["device_class"] = "garage" }
            if id.hasPrefix("binary_sensor.") { attributes["device_class"] = "door" }
            let raw = json(["entity_id": id, "state": value,
                            "last_changed": iso(observed.addingTimeInterval(-600 * Double(index + 1))),
                            "attributes": attributes])
            return (id, HaStateReading(entityID: id, json: raw, checkedAt: observed))
        })
    }

    static func doors(_ state: String) -> DoorsSnapshot {
        precondition(doorsStates.contains(state))
        if state == "loading" { return .loading }
        var config = base
        let ids = doorIDs(state) + (state == "partial_failure" ? ["binary_sensor.missing_door"] : [])
        config.doorsChosen = true
        config.doorIdsJson = json(state == "empty" ? [] : ids)
        if state == "setup" { return mapDoorsSnapshot(config: nil, readings: [:], errors: [:], now: now) }
        if state == "empty" { return mapDoorsSnapshot(config: config, readings: [:], errors: [:], now: now) }
        let failed = ["failed", "failed_history"].contains(state)
        let observed = ["history", "command_failed"].contains(state) ? old : now
        let readings = failed ? doorReplies(ids, state: state == "failed_history" ? "moving" : "ready", observed: old) :
            doorReplies(ids.filter { $0 != "binary_sensor.missing_door" }, state: state, observed: observed)
        let errors = failed ? Dictionary(uniqueKeysWithValues: ids.map { ($0, unreachable) }) :
            state == "command_failed" ? ["cover.garage": commandFailure] :
            state == "partial_failure" ? ["binary_sensor.missing_door": "Entity not found"] : [:]
        var snapshot = mapDoorsSnapshot(config: config, readings: readings, errors: errors, now: now)
        // Presentation only: the current account scope/revision can never match this origin.
        snapshot.actionScope = actionScope
        snapshot.actionRevision = actionRevision
        snapshot.operation = doorCommandOperation(state)
        return snapshot
    }

    private static func doorCommandOperation(_ state: String) -> DoorOperation? {
        let id: String
        let action: String
        switch state {
        case "opening_pending":
            id = "cover.side_gate"; action = "open"
        case "opening_pending_unavailable", "command_failed":
            id = "cover.garage"; action = "open"
        case "stop_pending":
            id = "cover.garage"; action = "stop"
        case "lock_pending":
            id = "lock.front"; action = "lock"
        default: return nil
        }
        return DoorOperation(id: commandOperation, entityID: id, action: action, startedAt: commandStarted,
            endedAt: state == "command_failed" ? now.addingTimeInterval(-5) : nil,
            error: state == "command_failed" ? commandFailure : nil, delivered: true)
    }

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
