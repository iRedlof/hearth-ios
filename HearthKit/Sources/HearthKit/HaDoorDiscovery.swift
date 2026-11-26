import Foundation

/// Default choices include eligible doors even while their live state is unavailable.
public func defaultDoorIDs(_ statesJSON: String, lockID: String) throws -> [String] {
    guard let data = statesJSON.data(using: .utf8),
          let values = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
        throw HaError("Unexpected doors reading")
    }
    var garages: [String] = [], sensors: [String] = []
    for value in values {
        guard isDoorEligibleObject(value), let id = value["entity_id"] as? String else { continue }
        let attributes = value["attributes"] as? [String: Any] ?? [:]
        let deviceClass = attributes["device_class"] as? String ?? ""
        if id.hasPrefix("cover.") { garages.append(id) }
        else if id.hasPrefix("binary_sensor."), ["door", "garage_door"].contains(deviceClass) {
            let name = attributes["friendly_name"] as? String ?? ""
            if name.range(of: "\\b(tilt|shock|vibration)\\b", options: [.regularExpression, .caseInsensitive]) == nil {
                sensors.append(id)
            }
        }
    }
    var seen = Set<String>()
    let lock = doorKindForID(lockID) == .lock ? [lockID] : []
    return (garages + sensors.sorted() + lock).filter { seen.insert($0).inserted }
}
