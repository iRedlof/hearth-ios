import CoreGraphics

/// What gives way, and in which order, when a two-panel widget is short of room (a small iPhone,
/// Larger text, long names). The views offer these to `ViewThatFits` first to last and SwiftUI
/// takes the first that fits the widget's height, so nothing overflows its box.

/// A tile grid (Lights, Quick actions, Favourites).
public struct PanelTileFit: Sendable, Equatable, Hashable {
    /// Grid rows shown; each holds `PanelLimits.tileColumns` tiles.
    public let rows: Int
    /// The pictured tile: glyph above the name (Lights, Favourites), names on two lines (Quick
    /// actions). When false the tile is one line shorter.
    public let roomy: Bool

    public var tileLimit: Int { rows * PanelLimits.tileColumns }

    /// All four tiles as pictured, then all four in the shorter form, then one row of two.
    public static let choices: [PanelTileFit] = [
        PanelTileFit(rows: PanelLimits.tileRows, roomy: true),
        PanelTileFit(rows: PanelLimits.tileRows, roomy: false),
        PanelTileFit(rows: 1, roomy: true),
        PanelTileFit(rows: 1, roomy: false),
    ]
}

/// A row list (Activity, Batteries): three rows, then two, then one.
public enum PanelRowFit {
    public static let choices: [Int] = Array((1...PanelLimits.maxRows).reversed())
}

/// A rail: the glyph and the answer shrink before any line of detail is given up.
public struct PanelRailFit: Sendable, Equatable, Hashable {
    public let iconSize: CGFloat
    /// The answer's size when it fits one line ("3 on").
    public let wordSize: CGFloat
    /// The answer's size when it may wrap ("3 not reporting").
    public let longWordSize: CGFloat
    /// Lines of detail kept; 0: none.
    public let detailLines: Int

    public static let choices: [PanelRailFit] = [
        PanelRailFit(iconSize: 34, wordSize: 25, longWordSize: 20, detailLines: 3),
        PanelRailFit(iconSize: 34, wordSize: 21, longWordSize: 17, detailLines: 3),
        PanelRailFit(iconSize: 26, wordSize: 21, longWordSize: 17, detailLines: 3),
        PanelRailFit(iconSize: 26, wordSize: 21, longWordSize: 17, detailLines: 2),
        PanelRailFit(iconSize: 22, wordSize: 18, longWordSize: 15, detailLines: 2),
        PanelRailFit(iconSize: 22, wordSize: 18, longWordSize: 15, detailLines: 1),
        PanelRailFit(iconSize: 22, wordSize: 18, longWordSize: 15, detailLines: 0),
    ]
}

/// `items` in rows of `columns`, in order; the last row may be short.
public func panelRows<Item>(_ items: [Item], columns: Int) -> [[Item]] {
    guard columns > 0 else { return [] }
    return stride(from: 0, to: items.count, by: columns).map { Array(items[$0..<min($0 + columns, items.count)]) }
}
