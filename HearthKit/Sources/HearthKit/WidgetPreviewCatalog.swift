/// The designed widget families, shared by the extension and the in-app gallery.
/// Add a family only after designing useful content for that size.
public enum WidgetPreviewFamily: String, CaseIterable, Sendable {
    case small
    case medium
    case large

    public var title: String {
        switch self {
        case .small: "Small"
        case .medium: "Medium"
        case .large: "Large"
        }
    }
}

public enum WidgetPreviewKind: String, CaseIterable, Identifiable, Sendable {
    case car
    case alarm
    case thermostat
    case chargepoint
    case battery
    case activity
    case lights
    case quick
    case favourites
    case doors

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .car: "Car"
        case .alarm: "Home Alarm"
        case .thermostat: "Thermostat"
        case .chargepoint: "ChargePoint"
        case .battery: "Batteries"
        case .activity: "Activity"
        case .lights: "Lights"
        case .quick: "Quick"
        case .favourites: "Favourites"
        case .doors: "Doors"
        }
    }

    /// Outline identity symbols. Device-action symbols belong to their production views.
    public var symbolName: String {
        switch self {
        case .car: "car"
        case .alarm: "shield"
        case .thermostat: "thermometer.medium"
        case .chargepoint: "bolt.circle"
        case .battery: "battery.100"
        case .activity: "clock"
        case .lights: "lightbulb"
        case .quick: "bolt"
        case .favourites: "star"
        case .doors: "door.left.hand.closed"
        }
    }

    public var family: WidgetPreviewFamily {
        switch self {
        case .car, .alarm, .thermostat, .chargepoint, .battery, .quick: .medium
        case .activity, .lights, .favourites, .doors: .large
        }
    }

    public var supportedFamilies: [WidgetPreviewFamily] {
        self == .thermostat || self == .car || self == .alarm ? [.small, .medium] : [family]
    }
}
