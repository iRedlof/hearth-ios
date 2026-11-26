import Foundation

/// A snapshot reading for a widget with health and state line.
public struct WidgetReading: Sendable {
    public let health: WidgetHealth
    public let stateLine: String

    public init(health: WidgetHealth, stateLine: String) {
        self.health = health
        self.stateLine = stateLine
    }
}

/// Builds HomeWidgetItems from configured widget kinds and their readings.
/// For each kind in `kinds`, creates a HomeWidgetItem with the reading's health and stateLine,
/// or defaults to .ok health and "Added" stateLine if no reading is provided.
/// Returns items sorted problems-first.
///
/// - Parameters:
///   - kinds: The widget kinds to build items for (in display order).
///   - readings: A dictionary mapping widget kinds to their current readings.
/// - Returns: Array of HomeWidgetItem sorted with problems first.
public func homeWidgetItems(
    kinds: [HomeWidgetKind],
    readings: [HomeWidgetKind: WidgetReading]
) -> [HomeWidgetItem] {
    let items = kinds.map { kind in
        let reading = readings[kind]
        return HomeWidgetItem(
            id: kind.rawValue,
            kind: kind,
            stateLine: reading?.stateLine ?? "Added",
            health: reading?.health ?? .ok,
            route: .widget(kind)
        )
    }
    return sortedProblemsFirst(items)
}
