import Foundation

public func doorKindForID(_ id: String) -> DoorKind? {
    let parts = id.split(separator: ".", omittingEmptySubsequences: false)
    guard parts.count == 2, !parts[1].isEmpty,
          parts[1].utf8.allSatisfy({ (UInt8(97)...UInt8(122)).contains($0)
              || (UInt8(48)...UInt8(57)).contains($0) || $0 == 95 })
    else { return nil }
    switch parts[0] {
    case "cover": return .garage
    case "binary_sensor": return .sensor
    case "lock": return .lock
    default: return nil
    }
}

func isDoorEligibleObject(_ object: [String: Any]) -> Bool {
    guard let id = object["entity_id"] as? String, let kind = doorKindForID(id) else { return false }
    let attributes = object["attributes"] as? [String: Any]
    let deviceClass = attributes?["device_class"] as? String ?? ""
    switch kind {
    case .garage: return ["garage", "gate"].contains(deviceClass)
    case .sensor: return ["door", "garage_door", "window", "opening"].contains(deviceClass)
    case .lock: return attributes?["entity_id"] == nil
    }
}

/// Settings may use the same eligibility policy as reading and discovery.
public func isDoorEligible(_ json: String) -> Bool {
    guard let data = json.data(using: .utf8),
          let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return false }
    return isDoorEligibleObject(object)
}

func validDoorState(_ kind: DoorKind, _ state: String) -> Bool {
    if ["unknown", "unavailable"].contains(state) { return true }
    switch kind {
    case .garage: return ["open", "closed", "opening", "closing"].contains(state)
    case .sensor: return ["on", "off"].contains(state)
    case .lock: return ["locked", "unlocked", "open", "opening", "locking", "unlocking", "jammed"].contains(state)
    }
}

public func doorFallbackName(_ id: String) -> String {
    let value = id.split(separator: ".", maxSplits: 1).last.map(String.init) ?? id
    let name = value.split(separator: "_").map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined(separator: " ")
    return name.isEmpty ? id : name
}

/// A chosen empty collection is intentional. Legacy defaults may include the configured front lock.
public func doorsSelectedIDs(_ config: HaConfig) -> [String] {
    var ids = config.doorIds
    if !config.doorsChosen && !config.lockId.isEmpty && !ids.contains(config.lockId) { ids.append(config.lockId) }
    var seen = Set<String>()
    return ids.filter { seen.insert($0).inserted }
}

/// Pending delivery changes the heading, never the last observed rows or check time.
public func doorsCommandPresentation(_ observed: DoorsSummary, operation: DoorOperation?) -> DoorsSummary {
    guard let operation, operation.pending, operation.error == nil,
          DoorAction(rawValue: operation.action) != nil else { return observed }
    return DoorsSummary(headline: "Updating doors…",
        tone: observed.tone == .calm ? .unknown : observed.tone,
        lockLine: observed.lockLine, rows: observed.rows)
}
