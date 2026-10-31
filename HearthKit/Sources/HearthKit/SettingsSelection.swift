import Foundation

public struct SelectionEdit: Sendable, Equatable {
    public let ids: [String]
    public let blockedByLimit: Bool
}

/// Picker transitions retain saved identity/order; limits apply only to additions.
public func selectionAfterToggle(_ before: [String], id: String, available: [String],
                                 limit: Int?) -> SelectionEdit {
    let current = preserveSelectionOrder(before, selected: Set(before), available: [])
    var selected = Set(current)
    if selected.contains(id) {
        selected.remove(id)
    } else {
        if let limit, current.count >= limit {
            return SelectionEdit(ids: current, blockedByLimit: true)
        }
        selected.insert(id)
    }
    return SelectionEdit(ids: preserveSelectionOrder(current, selected: selected, available: available),
                         blockedByLimit: false)
}
