/// The designed widget families, shared by the extension and the in-app gallery. Every widget is
/// medium and nothing else. Add a family only after designing useful content for that size.
public enum WidgetPreviewFamily: String, CaseIterable, Sendable {
    case medium

    public var title: String {
        switch self {
        case .medium: "Medium"
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
        }
    }

    /// The one size this widget is designed for.
    public var family: WidgetPreviewFamily { .medium }
}
