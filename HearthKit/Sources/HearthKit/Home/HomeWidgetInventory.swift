import Foundation

/// Widget kinds available for the iOS Home dashboard, ordered by their appearance priority.
public enum HomeWidgetKind: String, CaseIterable, Sendable {
    case car
    case alarm
    case thermostat
    case doors
    case quick
    case lights
    case favourites
    case activity
    case battery
    case chargePoint

    /// User-facing display name for this widget type.
    public var displayName: String {
        switch self {
        case .car: return "Car"
        case .alarm: return "Alarm"
        case .thermostat: return "Thermostat"
        case .doors: return "Doors"
        case .quick: return "Quick actions"
        case .lights: return "Lights"
        case .favourites: return "Favourites"
        case .activity: return "Activity"
        case .battery: return "Batteries"
        case .chargePoint: return "ChargePoint"
        }
    }

    /// SF Symbol icon for this widget type.
    public var icon: String {
        switch self {
        case .car: return "car.fill"
        case .alarm: return "shield.fill"
        case .thermostat: return "thermometer"
        case .doors: return "door.garage.closed"
        case .quick: return "bolt.fill"
        case .lights: return "lightbulb.fill"
        case .favourites: return "star.fill"
        case .activity: return "list.bullet"
        case .battery: return "battery.100"
        case .chargePoint: return "bolt.car.fill"
        }
    }

    /// Tile hue for this widget type, matching Phase-1 TileHue palette.
    public var hue: TileHue {
        switch self {
        case .car: return .green
        case .alarm: return .red
        case .thermostat: return .orange
        case .doors: return .blue
        case .quick: return .amber
        case .lights: return .amber
        case .favourites: return .purple
        case .activity: return .neutral
        case .battery: return .green
        case .chargePoint: return .green
        }
    }

    /// Widget preview kind for the gallery.
    public var previewKind: WidgetPreviewKind {
        switch self {
        case .car: return .car
        case .alarm: return .alarm
        case .thermostat: return .thermostat
        case .doors: return .doors
        case .quick: return .quick
        case .lights: return .lights
        case .favourites: return .favourites
        case .activity: return .activity
        case .battery: return .battery
        case .chargePoint: return .chargepoint
        }
    }
}

/// Returns the list of configured widgets based on the user's Home Assistant configuration
/// and ChargePoint sign-in status. Widgets appear in `HomeWidgetKind.allCases` order.
///
/// - Parameters:
///   - config: The Home Assistant configuration containing entity selections.
///   - chargePointSignedIn: Whether the user is signed into ChargePoint.
/// - Returns: Array of widget kinds that have the necessary configuration to be displayed.
public func configuredWidgets(config: HaConfig, chargePointSignedIn: Bool) -> [HomeWidgetKind] {
    HomeWidgetKind.allCases.filter { kind in
        switch kind {
        case .car:
            return config.carReady
        case .alarm:
            return config.isComplete
        case .thermostat:
            return config.hasClimate
        case .doors:
            return config.doorsChosen
        case .quick:
            return !config.scriptIds.isEmpty
        case .lights:
            return !config.lightPins.isEmpty
        case .favourites:
            return !config.favouriteIds.isEmpty
        case .activity, .battery:
            return !config.sensorIds.isEmpty
        case .chargePoint:
            return chargePointSignedIn
        }
    }
}
