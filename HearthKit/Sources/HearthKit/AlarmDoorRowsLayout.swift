import Foundation

/// Fixed vertical parts of the Alarm card's body, shared by the view and the layout tests.
public enum AlarmCardMetrics {
    public static let surfaceTopPadding = 11.0
    public static let surfaceBottomPadding = 6.0
    /// The full-width Arm / Disarm button under the door rows.
    public static let actionHeight = 34.0
}

/// The two compact door rows (front door, garage) in the middle of a medium Alarm card.
public enum AlarmDoorRowsMetrics {
    public static let rowCount = 2
    /// Clear space above and below the pair of rows.
    public static let margin = 5.0
    public static let rowSpacing = 4.0
    public static let maximumRowHeight = 38.0
    public static let rowVerticalPadding = 1.5
    public static let rowHorizontalPadding = 7.0
    public static let rowCornerRadius = 9.0
    /// `HearthFont.groupLabel` and `.caption`, before the card's text size.
    public static let nameSize = 13.0
    public static let statusSize = 11.0
    public static let buttonTextSize = 12.0
    /// Line height over point size; a little above Roboto Flex's 1.17 so the system font fits too.
    public static let lineHeightFactor = 1.2
    public static let maximumButtonHeight = 26.0
    /// Clear space above and below the trailing button inside its row.
    public static let buttonInset = 3.0
    public static let buttonHorizontalPadding = 7.0
    /// Both rows' pills share this least width ("Unlock" at the name size), so the two status lines
    /// get the same room and drop "since" together.
    public static let buttonMinimumWidth = 52.0
    public static let buttonCornerRadius = 8.0
    public static let minimumTextScale = 0.75
    /// Long names shrink to this before they truncate.
    public static let nameShrink = 0.8
    public static let iconScale = 0.85
    public static let iconSpacing = 4.0
    public static let contentSpacing = 6.0
}

public struct AlarmDoorRowsLayout: Sendable, Equatable {
    public let rowHeight: Double
    public let rowSpacing: Double
    /// The card's text size, lowered until a name and a status line fit one row.
    public let textScale: Double
    public let nameSize: Double
    public let statusSize: Double
    public let buttonTextSize: Double
    public let buttonHeight: Double
    public let buttonMinimumWidth: Double

    /// Both rows and the gap between them.
    public var contentHeight: Double {
        Double(AlarmDoorRowsMetrics.rowCount) * rowHeight + Double(AlarmDoorRowsMetrics.rowCount - 1) * rowSpacing
    }
    /// The name line plus the status line.
    public var textHeight: Double { AlarmDoorRowsMetrics.lineHeightFactor * (nameSize + statusSize) }
}

/// Sizes the two compact rows for the height left between the card's header and its arm button.
/// Rows share the space equally up to a cap; the text keeps the card's size where a row has room
/// for it and shrinks (never grows) where it does not, so both rows always fit.
public func alarmDoorRowsLayout(availableHeight: Double, textScale: Double) -> AlarmDoorRowsLayout {
    let metrics = AlarmDoorRowsMetrics.self
    let rows = Double(metrics.rowCount)
    let free = max(0, availableHeight - 2 * metrics.margin - (rows - 1) * metrics.rowSpacing)
    let rowHeight = min(metrics.maximumRowHeight, free / rows)
    let naturalText = metrics.lineHeightFactor * (metrics.nameSize + metrics.statusSize)
    let fitted = max(0, rowHeight - 2 * metrics.rowVerticalPadding) / naturalText
    let scale = max(metrics.minimumTextScale, min(textScale, fitted))
    return AlarmDoorRowsLayout(rowHeight: rowHeight, rowSpacing: metrics.rowSpacing, textScale: scale,
        nameSize: metrics.nameSize * scale, statusSize: metrics.statusSize * scale,
        buttonTextSize: metrics.buttonTextSize * scale,
        buttonHeight: max(0, min(metrics.maximumButtonHeight, rowHeight - 2 * metrics.buttonInset)),
        buttonMinimumWidth: metrics.buttonMinimumWidth * scale)
}
