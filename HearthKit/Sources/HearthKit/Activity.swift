import Foundation

/// What a logbook event is about (its icon). Ported from Android `ActivityState.kt`.
public enum ActivityKind: String, Sendable, Equatable { case alarm, lock, garage, door, charge, carLock }

/// Something that happened: when, what ("Garage closed"), and what did it (an automation), if known.
public struct ActivityItem: Sendable, Equatable {
    public let at: Date; public let kind: ActivityKind; public let text: String; public let by: String?
    public init(at: Date, kind: ActivityKind, text: String, by: String?) {
        self.at = at; self.kind = kind; self.text = text; self.by = by
    }
}

private func activityKindOf(_ id: String) -> ActivityKind {
    if id.hasPrefix("alarm_control_panel.") { return .alarm }
    if id.hasPrefix("lock.") { return .lock }
    if id.hasPrefix("cover.") { return .garage }
    if id.hasSuffix("_charge_cable") { return .charge }
    return .door
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

private let ACTIVITY_SETTLE: TimeInterval = 120

/// A real change keeps its time; a restart stamps everything at once — drop those. haStart nil = trust all.
public func trustedSince(_ since: Date?, _ haStart: Date?) -> Date? {
    guard let since, let haStart else { return since }
    let restartStamp = since >= haStart.addingTimeInterval(-60) && since < haStart.addingTimeInterval(ACTIVITY_SETTLE)
    return restartStamp ? nil : since
}

/// The logbook events for `names` (id → display name), newest first: only real changes. Ported from
/// Android `activityFrom` + `withoutGarageEchoes`.
public func activityFrom(_ logJson: String?, names: [String: String], haStart: Date?,
                         carIds: Set<String> = []) -> [ActivityItem] {
    guard let logJson, let data = logJson.data(using: .utf8),
          let arr = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]] else { return [] }
    let entries = arr.sorted {
        (parseOffsetDateTime($0["when"] as? String) ?? .distantPast)
            < (parseOffsetDateTime($1["when"] as? String) ?? .distantPast)
    }
    var last: [String: String] = [:]
    var items: [ActivityItem] = []
    for e in entries {
        let id = (e["entity_id"] as? String) ?? ""
        let state = (e["state"] as? String) ?? ""
        let prev = last[id]; last[id] = state
        if prev == state { continue }
        guard let name = names[id] else { continue }
        guard let at = parseOffsetDateTime(e["when"] as? String), trustedSince(at, haStart) != nil else { continue }
        var kind = activityKindOf(id)
        if kind == .lock && carIds.contains(id) { kind = .carLock }
        guard let text = activityEventText(kind, name, state) else { continue }
        let by = (e["context_event_type"] as? String) == "automation_triggered"
            ? activityByName(e["context_name"] as? String) : nil
        items.append(ActivityItem(at: at, kind: kind, text: text, by: by))
    }
    return withoutGarageEchoes(items).sorted { $0.at > $1.at }
}

/// The garage's own sensor echoing the opener ("Garage Door opened" after "Garage opened"): drop it.
private func withoutGarageEchoes(_ items: [ActivityItem]) -> [ActivityItem] {
    let garage = items.filter { $0.kind == .garage }
    return items.filter { d in
        guard d.kind == .door, d.text.range(of: "garage", options: .caseInsensitive) != nil else { return true }
        let dLast = d.text.split(separator: " ").last.map(String.init) ?? ""
        return !garage.contains { g in
            (g.text.split(separator: " ").last.map(String.init) ?? "") == dLast && abs(g.at.timeIntervalSince(d.at)) <= 90
        }
    }
}
