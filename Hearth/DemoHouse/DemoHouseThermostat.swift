#if DEBUG
import Foundation
import HearthKit

/// The fictional Hallway thermostat's saved reading. The Thermostat widget draws what was last read
/// and saved, so the demo house saves the same canned climate and room-sensor states the URL stub
/// serves; the thermostat detail screen (`ThermostatControlsScreen`, which needs a `.ticket`
/// destination) is opened from a ticket bound to that reading. DEBUG only.
enum DemoHouseThermostat {
    private static var entityIDs: [String] { [DemoHouseCatalog.climateID] + DemoHouseCatalog.sensorIDs }

    /// The canned states as the readings a live fetch would have stored.
    private static func readings(now: Date) -> [String: HaStateReading] {
        entityIDs.reduce(into: [:]) { readings, id in
            guard let object = DemoHouseCatalog.stateObject(for: id),
                  let data = try? JSONSerialization.data(withJSONObject: object),
                  let json = String(data: data, encoding: .utf8) else {
                NSLog("[DemoHouse] no canned state for \(id)")
                return
            }
            readings[id] = HaStateReading(entityID: id, json: json, checkedAt: now)
        }
    }

    /// Saves the readings under the just-seeded config, so Home's Thermostat tile, the Thermostat
    /// page and Card style draw the demo thermostat rather than "no saved reading".
    static func seedReadings() {
        guard let store = HaConfigStore.store, let context = HaConfigStore.context() else {
            NSLog("[DemoHouse] thermostat seed skipped: shared storage is unavailable")
            return
        }
        let now = Date()
        do { _ = try store.merge(readings(now: now), expectedScope: context.scope, checkedAt: now) }
        catch { NSLog("[DemoHouse] thermostat seed failed: \(error)") }
    }

    /// Returns a `.ticket` destination backed by a freshly persisted reading, or `nil` if the shared
    /// store is unavailable.
    static func makeDetailDestination() -> ThermostatDestination? {
        let now = Date()
        // Use the live request scope and current config so the saved ticket's selection matches the
        // live store: the detail then opens with live controls instead of a read-only "changed" note.
        let context = HaConfigStore.context()
        let snapshot = HaStoreSnapshot(config: context?.config ?? DemoHouseCatalog.config,
                                       scope: context?.scope ?? "demo-house", readings: readings(now: now))
        let envelope = thermostatEnvelope(snapshot, now: now, recovery: .none)
        let payload = ThermostatReadingsStore.bind(envelope, date: now)
        if case .ticket = payload.destination { return payload.destination }
        return nil
    }
}
#endif
