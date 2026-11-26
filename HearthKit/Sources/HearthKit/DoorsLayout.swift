import Foundation

public struct DoorsRowBudget: Sendable, Equatable {
    public let count: Int; public let rowHeight: Double; public let showOverflow: Bool; public let contentHeight: Double
    public let summaryOnly: Bool; public let padding: Double; public let headerHeight: Double
    public init(count: Int, rowHeight: Double, showOverflow: Bool, contentHeight: Double,
                summaryOnly: Bool = false, padding: Double = 15, headerHeight: Double = 0) {
        self.count = count; self.rowHeight = rowHeight; self.showOverflow = showOverflow; self.contentHeight = contentHeight
        self.summaryOnly = summaryOnly; self.padding = padding; self.headerHeight = headerHeight
    }
}

public struct DoorsCollectionLayout: Sendable, Equatable {
    public let budget: DoorsRowBudget; public let groups: [String]; public let lines: [String]
    public let fontSize: Double; public let lineHeight: Double; public let contentWidth: Double; public let fits: Bool
    public var priorityID: String? = nil
}

/// Measured card height and scaled fonts decide row count. Each row keeps identical fixed geometry.
public func doorsRowBudget(height: Double, fontScale: Double, rowCount: Int, hasError: Bool = false) -> DoorsRowBudget {
    let scale = fontScale.isFinite ? max(1, fontScale) : 1
    let available = (height.isFinite ? max(0, height) : 0) - 30
    let header = 52 * scale + (hasError ? 32 * scale : 0)
    let rowHeight = 54 * scale
    let gap: Double = 6
    let room = max(0, available - header - 8)
    func fits(_ space: Double) -> Int { Int(min(20, max(0, floor((space + gap) / (rowHeight + gap))))) }
    let total = max(0, rowCount)
    let needsOverflow = fits(room) < total
    let overflow = 36 * scale
    let showOverflow = needsOverflow && room >= overflow
    let count = min(total, fits(room - (showOverflow ? overflow : 0)))
    let rowsHeight = count == 0 ? 0 : Double(count) * rowHeight + Double(count - 1) * gap
    if total > 0 && count == 0 {
        let compactHeight = 3 * 18 * scale + 8
        let padding: Double = compactHeight + 30 <= height ? 15 : 4
        return DoorsRowBudget(count: 0, rowHeight: rowHeight, showOverflow: true,
            contentHeight: compactHeight, summaryOnly: true, padding: padding)
    }
    return DoorsRowBudget(count: count, rowHeight: rowHeight, showOverflow: showOverflow,
        contentHeight: header + 8 + rowsHeight + (showOverflow ? overflow : 0), headerHeight: header)
}

/// Monospaced group labels wrap at a conservative fixed advance without reducing their type size.
public func doorsCollectionLayout(width: Double, height: Double, fontScale: Double,
    rows: [DoorView], hasError: Bool = false, priorityID: String? = nil) -> DoorsCollectionLayout {
    let scale = fontScale.isFinite ? max(1, fontScale) : 1
    let header = (52 + (hasError ? 32 : 0)) * scale
    let rowHeight = 54 * scale
    let available = height - 30
    let room = available - header - 8
    let fullFit = Int(min(20, max(0, floor((room + 6) / (rowHeight + 6)))))
    if rows.isEmpty || fullFit >= rows.count {
        let count = min(20, rows.count)
        let consumed = header + 8 + Double(count) * rowHeight + Double(max(0, count - 1)) * 6
        return DoorsCollectionLayout(budget: DoorsRowBudget(count: count, rowHeight: rowHeight,
            showOverflow: false, contentHeight: consumed, headerHeight: header), groups: [], lines: [],
            fontSize: 12 * scale, lineHeight: 16 * scale, contentWidth: 0, fits: consumed <= available)
    }
    let upper = min(fullFit, rows.count - 1)
    if upper > 0 {
        for count in stride(from: upper, through: 1, by: -1) {
            if let priorityID, rows.filter({ $0.id == priorityID }).count == 1,
               !rows.prefix(count).contains(where: { $0.id == priorityID }) { continue }
            let groups = doorsSafetyGroups(Array(rows.dropFirst(count)))
            let fontSize = 12 * scale
            let lines = wrapDoorGroups(groups, width: width - 30, fontSize: fontSize)
            let lineHeight = 16 * scale
            let consumed = header + 8 + Double(count) * rowHeight + Double(count - 1) * 6 + 4 + Double(lines.count) * lineHeight
            if consumed <= available {
                return DoorsCollectionLayout(budget: DoorsRowBudget(count: count, rowHeight: rowHeight,
                    showOverflow: true, contentHeight: consumed, headerHeight: header), groups: groups,
                    lines: lines, fontSize: fontSize, lineHeight: lineHeight,
                    contentWidth: doorLinesWidth(lines, fontSize: fontSize), fits: true)
            }
        }
    }
    if let priorityID, rows.filter({ $0.id == priorityID }).count == 1 {
        let groups = doorsSafetyGroups(rows.filter { $0.id != priorityID })
        let fontSize = 12 * scale
        let lineHeight = 16 * scale
        for padding in [15.0, 4.0] {
            let lines = wrapDoorGroups(groups, width: width - 2 * padding, fontSize: fontSize)
            let gap = lines.isEmpty ? 0.0 : 4.0
            let consumed = rowHeight + gap + Double(lines.count) * lineHeight
            let contentWidth = doorLinesWidth(lines, fontSize: fontSize)
            if consumed + 2 * padding <= height, contentWidth + 2 * padding <= width {
                return DoorsCollectionLayout(budget: DoorsRowBudget(count: 1, rowHeight: rowHeight,
                    showOverflow: !lines.isEmpty, contentHeight: consumed, padding: padding),
                    groups: groups, lines: lines, fontSize: fontSize, lineHeight: lineHeight,
                    contentWidth: contentWidth, fits: true, priorityID: priorityID)
            }
        }
    }
    let groups = doorsSafetyGroups(rows)
    var fontSize = 14 * scale
    var lineHeight = 18 * scale
    var padding: Double = 15
    var lines = wrapDoorGroups(groups, width: width - 2 * padding, fontSize: fontSize)
    func consumed() -> Double { Double(lines.count) * lineHeight + Double(max(0, lines.count - 1)) * 4 }
    if consumed() + 2 * padding > height {
        padding = 4
        lines = wrapDoorGroups(groups, width: width - 2 * padding, fontSize: fontSize)
    }
    if consumed() + 2 * padding > height {
        fontSize = 12 * scale
        lineHeight = 16 * scale
        let compact = groups.map { $0.replacingOccurrences(of: "unavailable", with: "N/A") }.joined(separator: " ")
        lines = wrapDoorGroups([compact], width: width - 2 * padding, fontSize: fontSize)
    }
    let contentHeight = consumed()
    let contentWidth = doorLinesWidth(lines, fontSize: fontSize)
    return DoorsCollectionLayout(budget: DoorsRowBudget(count: 0, rowHeight: rowHeight,
        showOverflow: true, contentHeight: contentHeight, summaryOnly: true, padding: padding),
        groups: groups, lines: lines, fontSize: fontSize, lineHeight: lineHeight, contentWidth: contentWidth,
        fits: contentHeight + 2 * padding <= height && contentWidth + 2 * padding <= width)
}

private func doorLinesWidth(_ lines: [String], fontSize: Double) -> Double {
    Double(lines.map(\.count).max() ?? 0) * fontSize * 0.62
}

private func wrapDoorGroups(_ groups: [String], width: Double, fontSize: Double) -> [String] {
    let capacity = Int(max(1, min(Double(Int.max / 2), floor(max(0, width) / (fontSize * 0.62)))))
    return groups.flatMap { group -> [String] in
        var output: [String] = []
        var line = ""
        for word in group.split(separator: " ").map(String.init) {
            if word.count > capacity {
                if !line.isEmpty { output.append(line); line = "" }
                var remainder = word
                while remainder.count > capacity {
                    output.append(String(remainder.prefix(capacity)))
                    remainder = String(remainder.dropFirst(capacity))
                }
                line = remainder
            } else if line.isEmpty { line = word }
            else if line.count + 1 + word.count <= capacity { line += " \(word)" }
            else { output.append(line); line = word }
        }
        if !line.isEmpty { output.append(line) }
        return output
    }
}

public func doorsSafetyGroups(_ rows: [DoorView]) -> [String] {
    let open = rows.filter { $0.open == true }.count
    let unavailable = rows.filter { $0.open == nil }.count
    let shut = rows.filter { $0.open == false }.count
    return [open > 0 ? "\(open) open" : nil, unavailable > 0 ? "\(unavailable) unavailable" : nil,
            shut > 0 ? "\(shut) shut" : nil].compactMap { $0 }
}

public func doorsOverflowLine(_ rows: [DoorView]) -> String {
    doorsSafetyGroups(rows).joined(separator: " · ")
}
