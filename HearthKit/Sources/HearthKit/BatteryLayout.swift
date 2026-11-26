import Foundation

public enum BatteryHeaderMode: Sendable, Equatable { case full, compact, none }

public struct BatteryRowBudget: Sendable, Equatable {
    public let rows: Int
    public let rowHeight: Double
    public let showError: Bool
    public let showOverflow: Bool
    public let readingWidth: Double
    public let overflowLines: [String]
    public let overflowLineHeight: Double
    public let headerMode: BatteryHeaderMode
    public let padding: Double
    public let headerHeight: Double
    public let gap: Double
    public let contentHeight: Double
    public init(rows: Int, rowHeight: Double, showError: Bool, showOverflow: Bool, readingWidth: Double,
        overflowLines: [String] = [], overflowLineHeight: Double = 16, headerMode: BatteryHeaderMode = .full,
        padding: Double = 15, headerHeight: Double = 50, gap: Double = 8, contentHeight: Double = 0) {
        self.rows = rows; self.rowHeight = rowHeight; self.showError = showError
        self.showOverflow = showOverflow; self.readingWidth = readingWidth; self.overflowLines = overflowLines
        self.overflowLineHeight = overflowLineHeight; self.headerMode = headerMode
        self.padding = padding; self.headerHeight = headerHeight; self.gap = gap; self.contentHeight = contentHeight
    }
}

/// A conservative capacity bound for 12pt labels, keeping whole status counts together.
public func batteryOverflowLineWidth(_ text: String, fontScale: Double) -> Double {
    Double(text.reduce(0) { $0 + ($1 == " " ? 4 : ($1 == "i" || $1 == "l" ? 3 : 9)) }) * fontScale
}

private func overflowLines(_ rows: ArraySlice<BatteryRow>, width: Double, scale: Double, historical: Bool,
                          shortLabels: Bool) -> [String] {
    guard !rows.isEmpty else { return [] }
    let low = rows.filter(\.low).count
    let unavailable = rows.filter { !$0.available }.count
    let full = "\(unavailable) unavailable"
    let unavailableLabel = !shortLabels && batteryOverflowLineWidth(full, fontScale: scale) <= width ? full : "\(unavailable) N/A"
    var parts = ["\(rows.count) \(historical ? "saved" : "more")"]
    if low > 0 { parts.append("\(low) low") }
    if unavailable > 0 { parts.append(unavailableLabel) }
    var lines: [String] = []
    for part in parts {
        let separator = shortLabels ? " " : " · "
        if let last = lines.last, batteryOverflowLineWidth("\(last)\(separator)\(part)", fontScale: scale) <= width {
            lines[lines.count - 1] = "\(last)\(separator)\(part)"
        } else { lines.append(part) }
    }
    return lines
}

/// Explicit count lines and their exact reserved heights are also used by BatteryView.
public func batteryCollectionBudget(width: Double, height: Double, fontScale: Double, rows: [BatteryRow],
                                    hasError: Bool, compact: Bool = false) -> BatteryRowBudget {
    let scale = fontScale.isFinite && fontScale > 0 ? max(1, fontScale) : 1
    let safeHeight = height.isFinite ? max(0, height) : 0
    let safeWidth = width.isFinite ? max(0, width) : 0
    let rowHeight = 26 * scale
    let lineHeight = 16 * scale
    for mode in [BatteryHeaderMode.full, .compact, .none] {
        let padding = mode == .full ? 15.0 : 6.0
        let header: Double = switch mode {
        case .full: (compact ? 44 : 50) * scale
        case .compact: max(36, lineHeight)
        case .none: 0
        }
        let gap: Double = switch mode { case .full: 8; case .compact: 4; case .none: 0 }
        let errorOptions = hasError && mode == .none ? [true, false] : [hasError]
        for showError in errorOptions {
            let errorHeight = showError ? 6 + 16 * scale : 0
            for fit in stride(from: min(rows.count, 27), through: 0, by: -1) {
                let lines = overflowLines(rows.dropFirst(fit), width: safeWidth - 2 * padding, scale: scale,
                    historical: hasError && mode == .none && !showError, shortLabels: mode == .none)
                let used = 2 * padding + header + gap + Double(fit) * rowHeight + Double(lines.count) * lineHeight + errorHeight
                if used <= safeHeight {
                    return BatteryRowBudget(rows: fit, rowHeight: rowHeight, showError: showError,
                        showOverflow: !lines.isEmpty, readingWidth: 86 * scale, overflowLines: lines,
                        overflowLineHeight: lineHeight, headerMode: mode, padding: padding,
                        headerHeight: header, gap: gap, contentHeight: used)
                }
            }
        }
    }
    return BatteryRowBudget(rows: 0, rowHeight: rowHeight, showError: false, showOverflow: false,
                            readingWidth: 86 * scale, headerMode: .none, padding: 0)
}

/// Height and scaled type determine the rows, including reserved error and overflow lines.
public func batteryRowBudget(height: Double, fontScale: Double, totalRows: Int, hasError: Bool,
                             compact: Bool = false) -> BatteryRowBudget {
    let scale = fontScale.isFinite && fontScale > 0 ? max(1, fontScale) : 1
    let safeHeight = height.isFinite ? max(0, height) : 0
    let header = (compact ? 44.0 : 50.0) * scale
    let row = 26 * scale
    let room = max(0, safeHeight - 30 - header - 8)
    let errorHeight = hasError ? 6 + 16 * scale : 0
    let available = max(0, room - errorHeight)
    let overflowHeight = 18 * scale
    var fit = min(max(0, totalRows), min(27, Int(min(27, available / row))))
    if fit < totalRows { fit = min(max(0, totalRows), Int(min(27, max(0, available - overflowHeight) / row))) }
    return BatteryRowBudget(rows: fit, rowHeight: row, showError: hasError && room >= errorHeight,
                            showOverflow: fit < totalRows && available - Double(fit) * row >= overflowHeight,
                            readingWidth: 86 * scale)
}

public func batteryOverflow(_ rows: [BatteryRow]) -> String? {
    guard !rows.isEmpty else { return nil }
    var labels = ["\(rows.count) more"]
    let low = rows.filter(\.low).count
    let unavailable = rows.filter { !$0.available }.count
    if low > 0 { labels.append("\(low) low") }
    if unavailable > 0 { labels.append("\(unavailable) unavailable") }
    return labels.joined(separator: " · ")
}
