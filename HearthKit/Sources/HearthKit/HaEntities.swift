import Foundation

/// A Home Assistant entity as listed by `GET /api/states` — just the fields a settings
/// picker needs. Mirrors the Android settings entity list (`SettingsModel.kt`).
public struct HaEntity: Sendable, Equatable, Identifiable {
    public let id: String      // entity_id, e.g. "alarm_control_panel.home"
    public let name: String    // friendly_name, else the entity_id
    public init(id: String, name: String) { self.id = id; self.name = name }

    /// The domain is the part before the first dot (e.g. "alarm_control_panel").
    public var domain: String { String(id.prefix { $0 != "." }) }
}

/// Parse a `GET /api/states` array into entities. Non-array/garbage JSON yields `[]`
/// (HA error bodies like `{"message":...}` or an HTML 502 are not a state list).
public func parseEntities(_ statesJson: String) -> [HaEntity] {
    guard let data = statesJson.data(using: .utf8),
          let arr = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]]
    else { return [] }
    return arr.compactMap { obj in
        guard let id = obj["entity_id"] as? String, !id.isEmpty else { return nil }
        let friendly = (obj["attributes"] as? [String: Any])?["friendly_name"] as? String
        let name = friendly.flatMap { $0.isEmpty ? nil : $0 } ?? id
        return HaEntity(id: id, name: name)
    }
}

/// Entities in one domain (e.g. "alarm_control_panel"), sorted by display name.
public func entitiesInDomain(_ entities: [HaEntity], _ domain: String) -> [HaEntity] {
    entities
        .filter { $0.domain == domain }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
}
