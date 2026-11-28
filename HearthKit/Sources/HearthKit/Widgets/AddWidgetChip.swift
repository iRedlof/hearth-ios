import Foundation

/// Widget chip state for the Add Widget gallery.
public enum AddChip: Sendable, Equatable {
    case added        // Widget is configured and can be placed (green "Added")
    case ready        // Home Assistant is connected; the widget just needs its own setup (green "Ready to set up")
    case needsHA      // Requires Home Assistant connection (grey "Needs Home Assistant")
    case needsCP      // Requires ChargePoint sign-in (grey "Needs ChargePoint")
}

/// Widget category for grouping in the Add Widget gallery.
public enum AddCategory: String, CaseIterable, Sendable {
    case control = "Control"
    case check = "Check"
    case carCharging = "Car & charging"
}

/// Returns the chip state for a widget kind based on current configuration.
/// - Parameters:
///   - kind: The widget kind to check
///   - config: Home Assistant configuration
///   - cpSignedIn: Whether ChargePoint is signed in
/// - Returns: The chip state indicating availability and requirements
public func addWidgetChip(kind: HomeWidgetKind, config: HaConfig, cpSignedIn: Bool) -> AddChip {
    let configured = configuredWidgets(config: config, chargePointSignedIn: cpSignedIn)

    // Widget is configured and ready to be placed
    if configured.contains(kind) {
        return .added
    }

    // Widget needs setup
    switch kind {
    case .chargePoint:
        return .needsCP
    default:
        // Connected to Home Assistant: nothing is missing but this widget's own choices. Saying
        // "Needs Home Assistant" here read as if Home Assistant were not signed in.
        return haConnectionStatus(config) == .connected ? .ready : .needsHA
    }
}

/// Returns the category for a widget kind.
/// - Parameter kind: The widget kind to categorize
/// - Returns: The category this widget belongs to
public func addWidgetCategory(_ kind: HomeWidgetKind) -> AddCategory {
    switch kind {
    case .alarm, .thermostat, .lights, .favourites, .quick:
        return .control
    case .doors, .activity, .battery:
        return .check
    case .car, .chargePoint:
        return .carCharging
    }
}
