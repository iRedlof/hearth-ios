import Foundation

/// The garage the Alarm card shows and may command. A saved choice wins (empty is None). With
/// nothing saved, the one `cover.*` in the old Doors selection is used; two or more are not
/// guessed between.
public func garageSelectedID(_ config: HaConfig) -> String? {
    if let saved = config.garageId { return doorKindForID(saved) == .garage ? saved : nil }
    var seen = Set<String>()
    let covers = config.doorIds.filter { doorKindForID($0) == .garage && seen.insert($0).inserted }
    return covers.count == 1 ? covers.first : nil
}

/// Covers that can be the garage: `device_class` garage or gate, the eligibility the reader and
/// the command path apply. Sorted by name for the Settings picker. Like `parseEntities`, a body
/// that is not a state list (an HA error, an HTML 502) offers nothing.
public func garageDoorEntities(_ statesJSON: String) -> [HaEntity] {
    guard let data = statesJSON.data(using: .utf8),
          let rows = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]] else { return [] }
    return rows.compactMap { row -> HaEntity? in
        guard isDoorEligibleObject(row), let id = row["entity_id"] as? String,
              doorKindForID(id) == .garage else { return nil }
        let friendly = (row["attributes"] as? [String: Any])?["friendly_name"] as? String
        return HaEntity(id: id, name: friendly.flatMap { $0.isEmpty ? nil : $0 } ?? id)
    }
    .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
}
