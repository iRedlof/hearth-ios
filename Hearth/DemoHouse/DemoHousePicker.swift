#if DEBUG
import SwiftUI
import HearthKit

/// Render harness (docs/RENDER-HARNESS.md): `-demoPicker <name>` opens one of the real entity
/// pickers over the demo Home, so the walker can capture it (and its search field) without tapping
/// through a widget page. A pick is not saved: the demo house stays as seeded. DEBUG only.
enum DemoHousePicker: String, CaseIterable, Identifiable {
    case alarm, lock, garage, thermostat, sensors, lights, scripts, favourites

    var id: String { rawValue }

    static func requested(in arguments: [String]) -> DemoHousePicker? {
        guard let index = arguments.firstIndex(of: "-demoPicker"), index + 1 < arguments.count else { return nil }
        return DemoHousePicker(rawValue: arguments[index + 1])
    }
}

/// The picker as its widget page presents it (same title, domains, limit and current selection).
struct DemoHousePickerHost: View {
    let picker: DemoHousePicker
    let config: HaConfig

    private enum Limit {
        static let scripts = 6
        static let favourites = 12
    }

    var body: some View {
        NavigationStack { content }
    }

    @ViewBuilder private var content: some View {
        switch picker {
        case .alarm:
            single("Alarm panel", domain: "alarm_control_panel", selected: config.entityId)
        case .lock:
            single("Front door", domain: "lock", allowNone: true, selected: config.lockId)
        case .garage:
            single("Garage door", domain: "cover", allowNone: true,
                   selected: garageSelectedID(config) ?? "", garagesOnly: true)
        case .thermostat:
            single("Thermostat", domain: "climate", selected: config.climateId)
        case .sensors:
            multiple("Room sensors", domains: ["sensor", "binary_sensor"], selected: config.sensorIds)
        case .lights:
            multiple("Always show", domains: ["light"], selected: Array(config.lightPins))
        case .scripts:
            multiple("Scripts", domains: ["script"], selected: config.scriptIds, limit: Limit.scripts)
        case .favourites:
            multiple("Tiles", domains: ["switch", "light", "fan", "input_boolean", "script"],
                     selected: config.favouriteIds, limit: Limit.favourites)
        }
    }

    private func single(_ title: String, domain: String, allowNone: Bool = false, selected: String,
                        garagesOnly: Bool = false) -> some View {
        EntityPickerView(config: config, domain: domain, title: title, allowNone: allowNone,
                         selected: selected, garagesOnly: garagesOnly) { _ in }
    }

    private func multiple(_ title: String, domains: [String], selected: [String],
                          limit: Int? = nil) -> some View {
        MultiEntityPickerView(config: config, domains: domains, title: title, selected: selected,
                              limit: limit) { _ in }
    }
}
#endif
