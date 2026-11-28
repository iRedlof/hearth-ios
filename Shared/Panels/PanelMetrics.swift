import SwiftUI

/// The sizes the two-panel widgets share. Text sizes come from `HearthFont` and the Card style's
/// text size; these are the fixed parts around them.
enum PanelMetrics {
    // Rail
    static let railHorizontalPadding: CGFloat = 13
    static let railVerticalPadding: CGFloat = 12
    static let railGlyphGap: CGFloat = 4
    static let railDetailGap: CGFloat = 3
    static let railWordTracking: CGFloat = -0.5
    /// A one-line answer shrinks this far before it is cut.
    static let railWordShrink: CGFloat = 0.6
    /// A detail line is tried at this size on one line before it wraps.
    static let railDetailShrink: CGFloat = 0.88
    static let railFade: Double = 0.88
    static let railDetailOpacity: Double = 0.82

    // Body
    static let bodyHorizontalPadding: CGFloat = 13
    static let bodyTopPadding: CGFloat = 9
    static let bodyBottomPadding: CGFloat = 6
    /// Between the header, the notice and the items.
    static let sectionGap: CGFloat = 5
    static let noticeGap: CGFloat = 4
    static let secondaryOpacity: Double = 0.78
    static let faintOpacity: Double = 0.62
    static let dimGlyphOpacity: Double = 0.45

    // Header
    static let titleSize: CGFloat = 16
    static let headerSpacing: CGFloat = 6
    /// The title's size is tried at each of these before the "Checked" stamp is given up.
    static let titleShrinkSteps: [CGFloat] = [1, 0.9, 0.8]

    // Prompt ("Connect Home Assistant" + Connect)
    static let promptWellMaximumHeight: CGFloat = 72
    static let promptWellRadius: CGFloat = 13
    static let promptButtonHeight: CGFloat = 34
    static let promptButtonRadius: CGFloat = 10
    static let promptMessageShrink: CGFloat = 0.8

    // Tiles and chips
    static let gridSpacing: CGFloat = 6
    static let tileRadius: CGFloat = 11
    static let tileHorizontalPadding: CGFloat = 8
    static let tileVerticalPadding: CGFloat = 4
    static let tileMaximumHeight: CGFloat = 56
    static let tileGlyphSize: CGFloat = 11
    static let tileGlyphGap: CGFloat = 4
    static let tileLineGap: CGFloat = 1
    static let chipMinimumHeight: CGFloat = 32
    static let chipMaximumHeight: CGFloat = 50
    static let chipVerticalPadding: CGFloat = 5
    static let chipRoomyNameLines = 2
    static let nameShrink: CGFloat = 0.85

    // Rows
    static let rowSpacing: CGFloat = 2
    static let rowVerticalPadding: CGFloat = 2
    static let rowMaximumHeight: CGFloat = 30
    static let rowColumnGap: CGFloat = 6
    /// Wide enough for a same-day time ("10:30 AM") at the card's Normal text size; a time with
    /// its day ("Yest 9:30 PM") wraps under itself.
    static let activityTimeWidth: CGFloat = 49
    static let activityGlyphWidth: CGFloat = 14
    static let activityTextLines = 2
    static let moreGap: CGFloat = 2
}
