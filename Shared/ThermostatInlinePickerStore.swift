import Foundation
import WidgetKit
import os.log
import HearthKit

/// The opened Mode/Fan row is one App Group record, so both intents and the timeline provider agree on it.
/// Decisions about that record (matching, lifetime, selection) live in HearthKit.
enum ThermostatInlinePickerStore {
    private static let key = "thermostatInlinePicker"
    private static let widgetKind = "com.rohit.hearth.thermostat"
    private static let logger = Logger(subsystem: "com.rohit.hearth", category: "ThermostatInlinePicker")
    private static var defaults: UserDefaults { UserDefaults(suiteName: HaConfigStore.appGroup) ?? .standard }

    static func load() -> ThermostatInlinePicker? {
        guard let data = defaults.data(forKey: key) else { return nil }
        do { return try JSONDecoder().decode(ThermostatInlinePicker.self, from: data) }
        catch {
            // An unreadable record can only mean a closed row; it is never repaired or guessed.
            logger.error("Discarding unreadable inline picker record: \(error.localizedDescription, privacy: .public)")
            clear()
            return nil
        }
    }

    static func save(_ record: ThermostatInlinePicker) throws {
        defaults.set(try JSONEncoder().encode(record), forKey: key)
    }

    static func clear() { defaults.removeObject(forKey: key) }

    static func choices(for snapshot: ThermostatSnapshot, now: Date = .now) -> ThermostatInlineChoices? {
        thermostatInlineChoices(record: load(), now: now, snapshot: snapshot)
    }

    static func reloadWidget() { WidgetCenter.shared.reloadTimelines(ofKind: widgetKind) }
}

/// A newer Mode/Fan tap, or a choice, retires an open request that is still reading the thermostat.
@MainActor enum ThermostatInlinePickerOpening {
    private static var lifetime: ThermostatRequestLifetime?

    static func reserve() -> ThermostatRequestLifetime {
        retire()
        let next = ThermostatRequestLifetime()
        lifetime = next
        return next
    }

    static func retire() {
        lifetime?.invalidate()
        lifetime = nil
    }
}
