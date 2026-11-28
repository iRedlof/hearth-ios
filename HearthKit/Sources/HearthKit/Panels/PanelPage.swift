import Foundation

/// How much a medium two-panel body holds.
public enum PanelLimits {
    public static let tileColumns = 2
    public static let tileRows = 2
    /// Lights, Quick actions, Favourites: a 2×2 grid.
    public static let maxTiles = tileColumns * tileRows
    /// Activity, Batteries: three rows.
    public static let maxRows = 3
}

/// The items a body shows and how many it leaves out.
public struct PanelPage<Item: Sendable>: Sendable {
    public let shown: [Item]
    public let hiddenCount: Int

    /// "+2 more", or nil when everything is shown.
    public var moreLabel: String? { hiddenCount > 0 ? "+\(hiddenCount) more" : nil }
}

/// The first `limit` items, and the count of the rest.
public func panelPage<Item: Sendable>(_ items: [Item], limit: Int) -> PanelPage<Item> {
    let shown = Array(items.prefix(max(0, limit)))
    return PanelPage(shown: shown, hiddenCount: items.count - shown.count)
}
