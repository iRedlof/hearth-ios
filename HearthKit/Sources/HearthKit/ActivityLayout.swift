import Foundation

public struct ActivityDisplayParts: Sendable, Equatable {
    public let name: String; public let action: String
}

/// Older cached rows have one label. Recognize only known actions when separating the name.
public func activityDisplayParts(_ item: ActivityItem) -> ActivityDisplayParts {
    if !item.name.isEmpty && !item.action.isEmpty { return ActivityDisplayParts(name: item.name, action: item.action) }
    let actions = ["armed custom bypass", "armed (bypass)", "armed vacation", "armed night", "armed away", "armed home",
                   "alarm triggered", "plugged in", "unplugged", "disarmed", "triggered", "unlocked", "locked", "jammed", "opened", "closed", "open"]
    let action = actions.first { item.text.hasSuffix(" " + $0) } ?? item.action
    let name = !action.isEmpty && item.text.hasSuffix(" " + action) ? String(item.text.dropLast(action.count + 1)) : item.text
    return ActivityDisplayParts(name: name, action: action)
}

public func activityInWindow(_ items: [ActivityItem], now: Date) -> [ActivityItem] {
    let start = now.addingTimeInterval(-24 * 3600)
    return items.filter { $0.at >= start && $0.at <= now }.sorted(by: activityNewestFirst)
}

public enum ActivityRowMode: Sendable, Equatable { case inline, timeBelow, stacked }
public struct ActivityRowLayout: Sendable, Equatable {
    public let item: ActivityItem; public let height: Double; public let actionLines: Int; public let timeLines: Int
}
public struct ActivityLayout: Sendable, Equatable {
    public let shown: [ActivityItem]; public let hiddenCount: Int; public let narrow: Bool
    public let rowMode: ActivityRowMode; public let rows: [ActivityRowLayout]
    public let timeWidth: Double; public let actionWidth: Double
    public let headlineLines: Int; public let countLines: Int; public let checkedLines: Int
    public let summaryOnly: Bool; public let showSummaryTitle: Bool; public let padding: Double
    public let summaryLabel: String; public let usedHeight: Double; public let checkedText: String?
}

/// Conservative glyph widths choose allocation and wrapping while preserving the intended size.
func activityTextWidth(_ text: String, size: Double) -> Double {
    text.reduce(0.0) { total, c in
        let width: Double
        if c.isWhitespace { width = 0.32 }
        else if "MWmw".contains(c) { width = 0.90 }
        else if c.isUppercase { width = 0.72 }
        else if c.isNumber { width = 0.65 }
        else { width = 0.64 }
        return total + width
    } * size * 1.08
}

private func activityTextLines(_ text: String, width: Double, size: Double) -> Int {
    if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return 1 }
    let room = max(1, width)
    var lines = 1; var used = 0.0
    for word in text.split(whereSeparator: \.isWhitespace) {
        let need = activityTextWidth(String(word), size: size)
        let gap = used == 0 ? 0 : activityTextWidth(" ", size: size)
        if used > 0 && used + gap + need > room { lines += 1; used = 0 }
        let pieces = max(1, Int(ceil(need / room)))
        lines += pieces - 1
        used = pieces > 1 ? need - Double(pieces - 1) * room : used + (used == 0 ? 0 : gap) + need
    }
    return lines
}

public func activityLayout(width: Double, height: Double, fontScale: Double, items: [ActivityItem], hasError: Bool,
                           now: Date = Date(), headline: String = "Activity", checkedText: String? = nil) -> ActivityLayout {
    let scale = max(1, fontScale)
    let inner = max(1, width - 28)
    let actionWidth = items.map { activityTextWidth(activityDisplayParts($0).action, size: 13 * scale) }.max() ?? 0
    let timeWidth = items.map { activityTextWidth(activityTimeLabel($0.at, now: now), size: 11 * scale) }.max() ?? 0
    let minimumName = 44 * scale
    let mode: ActivityRowMode
    if timeWidth + 8 + 16 + 8 + minimumName + 5 + actionWidth <= inner { mode = .inline }
    else if minimumName + 5 + actionWidth <= inner - 24 { mode = .timeBelow }
    else { mode = .stacked }
    let rowRoom = max(1, inner - 24 - (mode == .inline ? timeWidth + 8 : 0))
    let allRows = items.map { item in
        let actionLines = mode == .stacked ? activityTextLines(activityDisplayParts(item).action, width: rowRoom, size: 13 * scale) : 1
        let timeLines = mode == .inline ? 0 : activityTextLines(activityTimeLabel(item.at, now: now), width: rowRoom, size: 11 * scale)
        let mainLines = mode == .stacked ? 1 + actionLines : 1
        let height = 18 * scale * Double(mainLines) + 16 * scale * Double(timeLines + (item.by != nil ? 1 : 0)) + 8
        return ActivityRowLayout(item: item, height: height, actionLines: actionLines, timeLines: timeLines)
    }
    let headerLines = activityTextLines(headline, width: max(1, inner - 44), size: 19 * scale)
    let header = max(36, 16 * scale + 24 * scale * Double(headerLines) + 2)
    let checkedLines = checkedText.map { activityTextLines($0, width: inner, size: 11 * scale) } ?? 0
    let failure = hasError ? 4 + 16 * scale : 0
    let stampHeight = checkedLines > 0 ? 2 + 16 * scale * Double(checkedLines) : 0
    let chrome = 28 + header + failure + stampHeight + 8
    let room = max(0, height - chrome)
    func fit(_ budget: Double) -> [ActivityRowLayout] {
        var remaining = budget
        var shown: [ActivityRowLayout] = []
        for row in allRows.prefix(27) {
            if row.height > remaining { break }
            shown.append(row); remaining -= row.height
        }
        return shown
    }
    let allFit = fit(room)
    let countLines = activityTextLines("+\(items.count) more events", width: inner, size: 11 * scale)
    let countHeight = 16 * scale * Double(countLines)
    let shown = allFit.count == items.count ? allFit : fit(max(0, room - countHeight))
    if chrome > height || (!items.isEmpty && shown.isEmpty) {
        let summary = hasError ? "\(items.count) saved events" : "\(items.count) events"
        let summaryInner = max(1, width - 12)
        let summaryLines = activityTextLines(summary, width: summaryInner, size: 13 * scale)
        let title = hasError ? "Unavailable" : "Activity"
        let titleLines = activityTextLines(title, width: max(1, summaryInner - 44), size: 13 * scale)
        let summaryHeader = max(36, 18 * scale * Double(titleLines))
        let compactChecked = checkedText?.replacingOccurrences(of: "Last checked ", with: "Checked ")
            .replacingOccurrences(of: "last checked ", with: "Checked ")
        let stampLines = compactChecked.map { activityTextLines($0, width: summaryInner, size: 11 * scale) } ?? 0
        let fullHeight = 12 + summaryHeader + 4 + 18 * scale * Double(summaryLines) +
            (stampLines > 0 ? 2 + 16 * scale * Double(stampLines) : 0)
        if fullHeight <= height {
            return ActivityLayout(shown: [], hiddenCount: items.count, narrow: mode != .inline, rowMode: mode, rows: [],
                timeWidth: timeWidth, actionWidth: actionWidth, headlineLines: titleLines, countLines: summaryLines,
                checkedLines: stampLines, summaryOnly: true, showSummaryTitle: true, padding: 6,
                summaryLabel: summary, usedHeight: fullHeight, checkedText: compactChecked)
        }
        var minimal = hasError || checkedText != nil ? "\(items.count) saved" : "\(items.count) events"
        func minimalAt(_ padding: Double) -> Int { activityTextLines(minimal, width: max(1, width - padding * 2), size: 13 * scale) }
        var chosenPadding = [8.0, 6, 4, 2, 0].first { 18 * scale * Double(minimalAt($0)) + $0 * 2 <= height }
        if chosenPadding == nil {
            minimal = String(items.count)
            chosenPadding = [8.0, 6, 4, 2, 0].first { 18 * scale * Double(minimalAt($0)) + $0 * 2 <= height }
        }
        let padding = chosenPadding ?? 0
        let minimalLines = minimalAt(padding)
        let content = 18 * scale * Double(minimalLines)
        return ActivityLayout(shown: [], hiddenCount: items.count, narrow: mode != .inline, rowMode: mode, rows: [],
            timeWidth: timeWidth, actionWidth: actionWidth, headlineLines: 0, countLines: minimalLines, checkedLines: 0,
            summaryOnly: true, showSummaryTitle: false, padding: padding, summaryLabel: minimal,
            usedHeight: content + 2 * padding, checkedText: nil)
    }
    let hidden = items.count - shown.count
    return ActivityLayout(shown: shown.map(\.item), hiddenCount: hidden, narrow: mode != .inline, rowMode: mode, rows: shown,
        timeWidth: timeWidth, actionWidth: actionWidth, headlineLines: headerLines, countLines: hidden > 0 ? countLines : 0,
        checkedLines: checkedLines, summaryOnly: false, showSummaryTitle: true, padding: 14, summaryLabel: "",
        usedHeight: chrome + shown.reduce(0) { $0 + $1.height } + (hidden > 0 ? countHeight : 0), checkedText: checkedText)
}

public func activityTimeLabel(_ at: Date, now: Date, zone: TimeZone = .current, locale: Locale = .current) -> String {
    var calendar = Calendar(identifier: .gregorian); calendar.timeZone = zone
    let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: at), to: calendar.startOfDay(for: now)).day ?? 0
    let f = DateFormatter(); f.timeZone = zone; f.locale = locale; f.dateFormat = "h:mm a"
    let time = f.string(from: at)
    if days == 0 { return time }
    if days == 1 { return "Yest \(time)" }
    f.dateFormat = "MMM d"
    return "\(f.string(from: at)) \(time)"
}

public func activitySnapshotHeadline(_ snapshot: ActivitySnapshot, now: Date) -> String {
    switch snapshot.state {
    case .setup: return "Connect Home Assistant"
    case .choose: return "Choose events"
    case .loading: return "Checking…"
    case .failed: return "History unavailable"
    case .ready, .empty:
        guard let latest = activityInWindow(snapshot.items, now: now).first else { return "No recent events" }
        if now.timeIntervalSince(latest.at) < 1800 {
            let parts = activityDisplayParts(latest)
            let action = parts.action.isEmpty ? "recent event" : parts.action
            return action.prefix(1).uppercased() + String(action.dropFirst())
        }
        return "Last event \(activityTimeLabel(latest.at, now: now))"
    }
}
