import Foundation

public struct DoorRowIdentity: Sendable, Equatable {
    public let label: String?
    public let identifiable: Bool
}

public func doorRowIdentities(_ rows: [DoorView], nameCapacity: Int, detailCapacity: Int) -> [String: DoorRowIdentity] {
    let capacity = max(1, nameCapacity)
    func prefix(_ row: DoorView) -> String {
        String(row.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().prefix(capacity))
    }
    func stem(_ id: String) -> String {
        String(id.split(separator: ".", maxSplits: 1).last ?? Substring(id)).replacingOccurrences(of: "_", with: " ")
    }
    let groups = Dictionary(grouping: rows, by: prefix)
    var result: [String: DoorRowIdentity] = [:]
    for row in rows {
        let collisions = groups[prefix(row)] ?? []
        if collisions.count < 2 { result[row.id] = DoorRowIdentity(label: nil, identifiable: true) }
        else {
            let short = stem(row.id)
            let label = collisions.filter { stem($0.id) == short }.count == 1
                ? short : row.id.replacingOccurrences(of: "_", with: " ")
            result[row.id] = DoorRowIdentity(label: label, identifiable: !label.isEmpty && label.count <= detailCapacity)
        }
    }
    return result
}
