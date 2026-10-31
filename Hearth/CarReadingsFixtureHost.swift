#if DEBUG
import SwiftUI
import HearthKit

/// Controlled native route proof. Its fake account/cache/tickets use a separate App Group folder;
/// ordinary HA settings and production widget timelines are not modified.
struct CarReadingsFixtureHost: View {
    let state: String
    @State private var runtime: CarReadingsRuntime?
    @State private var ticketID: UUID?
    @State private var error: String?

    var body: some View {
        Group {
            if let runtime {
                ContentView(carReadingsRuntime: runtime, inertTabs: true)
                    .safeAreaInset(edge: .top) {
                        VStack(spacing: 4) {
                            Text("Debug Car route · controlled data").font(.caption)
                            Button("Open fixture reading") { open() }
                                .frame(minHeight: 44)
                        }.frame(maxWidth: .infinity).background(.regularMaterial)
                    }
            } else if let error { Text(error).padding() }
            else { ProgressView("Preparing controlled reading") }
        }
        .task {
            guard runtime == nil else { return }
            do { try await prepare(); open() }
            catch { self.error = friendlyError(error) }
        }
    }

    private func open() {
        guard let ticketID else { return }
        Task { _ = try? await CarReadingsIntent(ticketID: ticketID).perform() }
    }

    private func prepare() async throws {
        guard let group = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: HaConfigStore.appGroup) else {
            throw HaError("Fixture shared storage unavailable")
        }
        let folder = group.appendingPathComponent("Library/Application Support/CarRouteFixtures/\(UUID())")
        let fakeConfig = HaConfig(baseUrl: "https://fixture.example", token: "inert-fixture", entityId: "")
        let stateStore = HaStateStore(directory: folder.appendingPathComponent("HA"),
            initialConfig: state == "setup" ? nil : fakeConfig, initialScope: UUID().uuidString)
        let tickets = CarReadingsTicketStore(directory: folder.appendingPathComponent("Tickets"))
        let now = Date()
        let raw = try Self.reply(battery: "79", now: now)
        let context = try stateStore.snapshot()
        var envelope = await fetchOwnedCarEnvelope(store: stateStore, context: context,
            now: now, request: { raw }, observedNow: { now })
        if state == "history" {
            let unknown = try Self.reply(battery: "unknown", now: now)
            envelope = await fetchOwnedCarEnvelope(store: stateStore, context: try stateStore.snapshot(),
                now: now, request: { unknown }, observedNow: { now.addingTimeInterval(1) })
        } else if state == "auth" {
            envelope = await fetchOwnedCarEnvelope(store: stateStore, context: try stateStore.snapshot(),
                now: now, request: { throw HaError("Authentication failed. Sign in to Home Assistant again.", code: 401) },
                observedNow: { now.addingTimeInterval(1) })
        }
        let issued = state == "expired" ? now.addingTimeInterval(-61) : now
        let ticket = try CarReadingsTicket(envelope: envelope, issuedAt: issued,
            lifetime: state == "expired" ? 60 : CarReadingsTicket.maximumLifetime)
        if state != "missing" { try tickets.save(ticket, now: issued) }
        if state == "changed" { try stateStore.saveConfig(nil) }
        let refreshed = try Self.reply(battery: "80", now: now)
        let refreshFails = state == "refresh_failure"
        runtime = CarReadingsRuntime(tickets: tickets, state: stateStore, request: {
            try await Task.sleep(for: .milliseconds(700))
            if refreshFails {
                throw HaError("Authentication failed. Sign in to Home Assistant again.", code: 401)
            }
            return refreshed
        }, reloadWidget: {
            "Controlled fixture: Home Screen widget refresh is not run."
        })
        ticketID = ticket.id
    }

    private static func reply(battery: String, now: Date) throws -> String {
        var values: [String: String] = [
            "sensor.battery_level": battery, "sensor.battery_range": "242.3", "number.charge_limit": "80",
            "sensor.charging": "disconnected", "binary_sensor.charge_cable": "off",
            "sensor.charger_power": "0", "sensor.time_to_full_charge": ISO8601DateFormatter().string(from: now.addingTimeInterval(-3600)),
            "sensor.charge_energy_added": "7.4", "lock.lock": "locked",
            "switch.sentry_mode": "unknown", "device_tracker.location": "home",
            "binary_sensor.status": "off", "sensor.odometer": "12504.75",
            "sensor.inside_temperature": "69.5", "sensor.outside_temperature": "55.2", "climate.climate": "off"
        ]
        for door in ["front_driver", "front_passenger", "rear_driver", "rear_passenger"] {
            values["binary_sensor.\(door)_door"] = "off"
        }
        for cover in ["frunk", "trunk", "windows", "charge_port_door"] { values["cover.\(cover)"] = "closed" }
        for wheel in ["front_left", "front_right", "rear_left", "rear_right"] {
            values["sensor.tire_pressure_\(wheel)"] = wheel == "rear_right" ? "unavailable" : "39.5"
            values["binary_sensor.tire_pressure_warning_\(wheel)"] = wheel == "rear_right" ? "unknown" : "off"
        }
        let object: [String: Any] = ["found": true, "prefix": "stargate",
            "name": "Stargate Premium — a long vehicle name for the full readings view",
            "s": values, "unit": "mi", "tempUnit": "°F", "pressureUnit": "psi",
            "statusSince": ISO8601DateFormatter().string(from: now.addingTimeInterval(-3600))]
        return String(decoding: try JSONSerialization.data(withJSONObject: object, options: .sortedKeys), as: UTF8.self)
    }
}
#endif
