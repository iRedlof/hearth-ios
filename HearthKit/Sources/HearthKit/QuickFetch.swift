import Foundation

/// A script key on the Quick widget.
public struct QuickKey: Sendable, Equatable {
    public let id: String; public let name: String
    public init(id: String, name: String) { self.id = id; self.name = name }
}

public struct QuickSnapshot: Sendable, Equatable {
    public let keys: [QuickKey]; public let checkedAt: String
    public init(keys: [QuickKey], checkedAt: String) { self.keys = keys; self.checkedAt = checkedAt }

    public static let sample = QuickSnapshot(keys: [
        QuickKey(id: "script.good_night", name: "Good Night"),
        QuickKey(id: "script.movie_time", name: "Movie Time"),
        QuickKey(id: "script.arrive_home", name: "Arrive Home"),
        QuickKey(id: "script.all_off", name: "All Off"),
    ], checkedAt: "9:41 AM")
}

/// A readable name from a script entity id — "script.good_night" → "Good night".
public func scriptShortName(_ id: String) -> String {
    let base = id.contains(".") ? id.split(separator: ".").dropFirst().joined(separator: ".") : id
    let words = base.replacingOccurrences(of: "_", with: " ").trimmingCharacters(in: .whitespaces)
    guard let first = words.first else { return id }
    return first.uppercased() + words.dropFirst()
}

/// The configured scripts (≤6) with their names, for the Quick widget. Names come from HA's
/// friendly_name, falling back to a tidied entity id.
public func fetchQuickSnapshot(_ config: HaConfig, now: Date = Date()) async -> QuickSnapshot {
    let checked = widgetClock(now)
    let ids = Array(config.scriptIds.prefix(6))
    guard config.baseUrl.hasPrefix("https://"), config.hasAuth, !ids.isEmpty else { return .sample }
    let client = HaClient(config)
    var keys: [QuickKey] = []
    for id in ids {
        let name = (try? await client.stateJson(id)).flatMap { friendlyName(ofStateJson: $0) } ?? scriptShortName(id)
        keys.append(QuickKey(id: id, name: name))
    }
    return QuickSnapshot(keys: keys, checkedAt: checked)
}
