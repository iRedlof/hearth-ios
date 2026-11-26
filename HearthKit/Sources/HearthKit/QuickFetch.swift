import Foundation

/// A script key on the Quick widget.
public struct QuickKey: Sendable, Equatable {
    public let id: String; public let name: String; public let available: Bool
    public init(id: String, name: String, available: Bool = true) {
        self.id = id; self.name = name; self.available = available
    }
}

public struct QuickSnapshot: Sendable, Equatable {
    public let keys: [QuickKey]; public let checkedAt: String
    public let state: TileSnapshotState; public let error: String?
    public init(keys: [QuickKey], checkedAt: String, state: TileSnapshotState = .ready, error: String? = nil) {
        self.keys = keys; self.checkedAt = checkedAt; self.state = state; self.error = error
    }
    public static let loading = QuickSnapshot(keys: [], checkedAt: "", state: .loading)

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
public func fetchQuickSnapshot(_ config: HaConfig?, now: Date = Date(),
    read: (@Sendable (String) async throws -> String)? = nil) async -> QuickSnapshot {
    guard let config, config.carReady else { return mapQuickSnapshot(config, replies: [:], now: now) }
    let client = HaClient(config)
    var replies: [String: Result<String, HaError>] = [:]
    for id in config.scriptIds.prefix(6) {
        do {
            let json: String
            if let read { json = try await read(id) } else { json = try await client.stateJson(id) }
            replies[id] = .success(json)
        } catch { replies[id] = .failure(HaError(tileReadError(error))) }
    }
    return mapQuickSnapshot(config, replies: replies, now: now)
}

public func mapQuickSnapshot(_ config: HaConfig?, replies: [String: Result<String, HaError>],
    now: Date = Date()) -> QuickSnapshot {
    let checked = widgetClock(now)
    guard let config, config.carReady else { return QuickSnapshot(keys: [], checkedAt: "", state: .setup) }
    let ids = Array(config.scriptIds.prefix(6))
    guard !ids.isEmpty else { return QuickSnapshot(keys: [], checkedAt: "", state: .choose) }
    var keys: [QuickKey] = []
    var errors: [String] = []
    var succeeded = false
    for id in ids {
        do {
            let json = try (replies[id] ?? .failure(HaError("No entity reading"))).get()
            let object = try tileStateObject(json, id: id)
            let name = friendlyName(ofStateJson: json) ?? scriptShortName(id)
            keys.append(QuickKey(id: id, name: name, available: id.hasPrefix("script.") &&
                                 ["on", "off"].contains(object["state"] as? String ?? "")))
            succeeded = true
        } catch {
            keys.append(QuickKey(id: id, name: scriptShortName(id), available: false))
            errors.append(tileReadError(error))
        }
    }
    return QuickSnapshot(keys: keys, checkedAt: succeeded ? checked : "",
                         state: succeeded ? .ready : .failed, error: errors.first)
}
