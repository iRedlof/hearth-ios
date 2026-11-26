import Foundation

/// Navigation routes for the iOS Home dashboard.
public enum HomeRoute: Sendable, Equatable {
    case widget(HomeWidgetKind)
    case homeAssistant
    case chargePoint
    case addWidget
    /// Card-style editor. `nil` = the global (all-widgets) style; a kind = that widget's override.
    case cardStyle(HomeWidgetKind?)
    case settings
    case leaveBy
    case travelDays
    case safetyAlerts
    case goodnight
}

/// A widget item for the iOS Home dashboard "Your widgets" strip.
public struct HomeWidgetItem: Identifiable, Sendable {
    public let id: String
    public let kind: HomeWidgetKind
    public let stateLine: String
    public let health: WidgetHealth
    public let route: HomeRoute

    public init(
        id: String,
        kind: HomeWidgetKind,
        stateLine: String,
        health: WidgetHealth,
        route: HomeRoute
    ) {
        self.id = id
        self.kind = kind
        self.stateLine = stateLine
        self.health = health
        self.route = route
    }
}

/// Sorts widget items with problems first, then healthy items.
/// Within each group, higher severity comes first. Ties preserve original order (stable).
///
/// - Parameter items: The unsorted widget items.
/// - Returns: Items sorted problems-first, by descending health severity, stably.
public func sortedProblemsFirst(_ items: [HomeWidgetItem]) -> [HomeWidgetItem] {
    items.enumerated()
        .sorted { lhs, rhs in
            let (lhsIndex, lhsItem) = lhs
            let (rhsIndex, rhsItem) = rhs

            let lhsSortsFirst = lhsItem.health.sortsFirst
            let rhsSortsFirst = rhsItem.health.sortsFirst

            // Problems before .ok
            if lhsSortsFirst != rhsSortsFirst {
                return lhsSortsFirst
            }

            // Within same sortsFirst group, higher severity (higher rawValue) first
            if lhsItem.health != rhsItem.health {
                return lhsItem.health > rhsItem.health
            }

            // Ties: preserve original order (stable)
            return lhsIndex < rhsIndex
        }
        .map(\.element)
}
