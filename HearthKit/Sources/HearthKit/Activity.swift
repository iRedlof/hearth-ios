import Foundation

/// What a logbook event is about (its icon). Ported from Android `ActivityState.kt`.
public enum ActivityKind: String, Sendable, Equatable, Codable { case alarm, lock, garage, door, charge, carLock }

/// Something that happened: when, what ("Garage closed"), and what did it (an automation), if known.
public struct ActivityItem: Sendable, Equatable, Codable {
    public let at: Date; public let kind: ActivityKind; public let text: String; public let by: String?
    public let entityId: String; public let name: String; public let action: String; public let eventKey: String
    public init(at: Date, kind: ActivityKind, text: String, by: String?,
                entityId: String = "", name: String = "", action: String = "", eventKey: String = "") {
        self.at = at; self.kind = kind; self.text = text; self.by = by
        self.entityId = entityId; self.name = name; self.action = action; self.eventKey = eventKey
    }

    private enum CodingKeys: String, CodingKey { case at, kind, text, by, entityId, name, action, eventKey }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(at: try c.decode(Date.self, forKey: .at), kind: try c.decode(ActivityKind.self, forKey: .kind),
                  text: try c.decode(String.self, forKey: .text), by: try c.decodeIfPresent(String.self, forKey: .by),
                  entityId: try c.decodeIfPresent(String.self, forKey: .entityId) ?? "",
                  name: try c.decodeIfPresent(String.self, forKey: .name) ?? "",
                  action: try c.decodeIfPresent(String.self, forKey: .action) ?? "",
                  eventKey: try c.decodeIfPresent(String.self, forKey: .eventKey) ?? "")
    }
}

private func activityKindOf(_ id: String) -> ActivityKind? {
    if id.hasPrefix("alarm_control_panel.") { return .alarm }
    if id.hasPrefix("lock.") { return .lock }
    if id.hasPrefix("cover.") { return .garage }
    if id.hasPrefix("binary_sensor.") && id.hasSuffix("_charge_cable") { return .charge }
    if id.hasPrefix("binary_sensor.") { return .door }
    return nil
}

/// "Garage closed", "Alarm armed home", "Front Door locked"; nil for in-between steps and no signal.
private func activityEventText(_ kind: ActivityKind, _ name: String, _ state: String) -> String? {
    switch kind {
    case .alarm:
        switch state {
        case "disarmed", "armed_home", "armed_away", "armed_night", "armed_vacation", "armed_custom_bypass", "triggered":
            return "\(name) \(statusFor(state).title.lowercased())"
        default: return nil
        }
    case .lock, .carLock:
        switch state {
        case "locked", "unlocked", "jammed", "open": return "\(name) \(lockStatusFor(state).title.lowercased())"
        default: return nil
        }
    case .garage:
        switch state { case "open": return "\(name) opened"; case "closed": return "\(name) closed"; default: return nil }
    case .charge:
        switch state { case "on": return "\(name) plugged in"; case "off": return "\(name) unplugged"; default: return nil }
    case .door:
        switch state { case "on": return "\(name) opened"; case "off": return "\(name) closed"; default: return nil }
    }
}

/// "[Ring][Armed & Home]: Routine" → "Ring Armed & Home routine".
private func activityByName(_ raw: String?) -> String? {
    guard let raw else { return nil }
    let cleaned = raw.replacingOccurrences(of: "[\\[\\]]", with: " ", options: .regularExpression)
        .replacingOccurrences(of: ":", with: " ")
        .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        .trimmingCharacters(in: .whitespaces)
        .replacingOccurrences(of: "\\bRoutine\\b", with: "routine", options: .regularExpression)
    return cleaned.isEmpty ? nil : cleaned
}

private let ACTIVITY_SETTLE: TimeInterval = 300

/// A real change keeps its time; a restart stamps everything at once — drop those. haStart nil = trust all.
public func trustedSince(_ since: Date?, _ haStart: Date?) -> Date? {
    guard let since, let haStart else { return since }
    let restartStamp = since >= haStart.addingTimeInterval(-60) && since < haStart.addingTimeInterval(ACTIVITY_SETTLE)
    return restartStamp ? nil : since
}

/// The logbook events for `names` (id → display name), newest first: only real changes. Ported from
/// Android `activityFrom` + `withoutGarageEchoes`.
public func activityFrom(_ logJson: String?, names: [String: String], haStart: Date?,
                         carIds: Set<String> = [], pairedSensors: [String: String] = [:], windowEnd: Date? = nil) -> [ActivityItem] {
    guard let logJson, let data = logJson.data(using: .utf8),
          let arr = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]] else { return [] }
    let entries = arr.sorted { a, b in
        let aTime = parseOffsetDateTime(a["when"] as? String) ?? .distantPast
        let bTime = parseOffsetDateTime(b["when"] as? String) ?? .distantPast
        if aTime != bTime { return aTime < bTime }
        for field in ["entity_id", "state", "context_name"] {
            let lhs = a[field] as? String ?? ""; let rhs = b[field] as? String ?? ""
            if lhs != rhs { return lhs < rhs }
        }
        return false
    }
    var last: [String: String] = [:]
    var items: [ActivityItem] = []
    for e in entries {
        let id = (e["entity_id"] as? String) ?? ""
        let state = (e["state"] as? String) ?? ""
        guard let name = names[id] else { continue }
        guard let at = parseOffsetDateTime(e["when"] as? String), trustedSince(at, haStart) != nil else { continue }
        if let windowEnd, at > windowEnd || at < windowEnd.addingTimeInterval(-24 * 3600) { continue }
        guard var kind = activityKindOf(id) else { continue }
        if kind == .lock && carIds.contains(id) { kind = .carLock }
        guard let action = activityEventText(kind, "", state)?.trimmingCharacters(in: .whitespaces) else { continue }
        if last[id] == action { continue }
        last[id] = action
        let by = (e["context_event_type"] as? String) == "automation_triggered"
            ? activityByName(e["context_name"] as? String) : nil
        items.append(ActivityItem(at: at, kind: kind, text: "\(name) \(action)", by: by,
                                  entityId: id, name: name, action: action,
                                  eventKey: "\(id)|\(action)|\(Int64((at.timeIntervalSince1970 * 1000).rounded()))"))
    }
    return withoutGarageEchoes(items, pairedSensors: pairedSensors).sorted(by: activityNewestFirst)
}

/// The garage's own sensor echoing the opener ("Garage Door opened" after "Garage opened"): drop it.
private func withoutGarageEchoes(_ items: [ActivityItem], pairedSensors: [String: String]) -> [ActivityItem] {
    let garage = items.filter { $0.kind == .garage }
    return items.filter { d in
        guard d.kind == .door, let coverId = pairedSensors[d.entityId] else { return true }
        return !garage.contains { g in
            g.entityId == coverId && g.action == d.action && abs(g.at.timeIntervalSince(d.at)) <= 90
        }
    }
}

func activityNewestFirst(_ a: ActivityItem, _ b: ActivityItem) -> Bool {
    if a.at != b.at { return a.at > b.at }
    if a.entityId != b.entityId { return a.entityId < b.entityId }
    if a.action != b.action { return a.action < b.action }
    return a.eventKey < b.eventKey
}
