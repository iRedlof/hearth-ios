import Foundation

public struct ActivityDisplayParts: Sendable, Equatable {
    public let name: String; public let action: String
}

/// Older cached rows have one label. Recognize only known actions when separating the name.
public func activityDisplayParts(_ item: ActivityItem) -> ActivityDisplayParts {
    if !item.name.isEmpty && !item.action.isEmpty { return ActivityDisplayParts(name: item.name, action: item.action) }
    let actions = ["armed custom bypass", "armed (bypass)", "armed vacation", "armed night", "armed away", "armed home",
                   "alarm triggered", "plugged in", "unplugged", "disarmed", "triggered", "unlocked", "locked", "jammed", "opened", "closed", "open"]
    let action = actions.first { item.text.hasSuffix(" " + $0) } ?? item.action
    let name = !action.isEmpty && item.text.hasSuffix(" " + action) ? String(item.text.dropLast(action.count + 1)) : item.text
    return ActivityDisplayParts(name: name, action: action)
}

public func activityInWindow(_ items: [ActivityItem], now: Date) -> [ActivityItem] {
    let start = now.addingTimeInterval(-24 * 3600)
    return items.filter { $0.at >= start && $0.at <= now }.sorted(by: activityNewestFirst)
}

/// "9:55 AM" today, "Yest 9:55 PM" yesterday, "Oct 28 9:55 AM" otherwise.
public func activityTimeLabel(_ at: Date, now: Date, zone: TimeZone = .current, locale: Locale = .current) -> String {
    var calendar = Calendar(identifier: .gregorian); calendar.timeZone = zone
    let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: at), to: calendar.startOfDay(for: now)).day ?? 0
    let f = DateFormatter(); f.timeZone = zone; f.locale = locale; f.dateFormat = "h:mm a"
    let time = f.string(from: at)
    if days == 0 { return time }
    if days == 1 { return "Yest \(time)" }
    f.dateFormat = "MMM d"
    return "\(f.string(from: at)) \(time)"
}
