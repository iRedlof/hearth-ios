import SwiftUI
import WidgetKit
import HearthKit

/// App settings — the single shared `HaConfig` every widget reads (matching Android's one global
/// config). Covers the Alarm (panel, front-door lock, confirm mode) and the Thermostat (climate,
/// resume button, room sensors). Every change builds a *new* `HaConfig` (value-type copy — never
/// mutate the live one), persists it to the App-Group store, and reloads all widget timelines.
struct SettingsView: View {
    @State private var config: HaConfig
    @State private var cpSignedIn = CpSessionStore.load().isSignedIn
    @State private var cpAuto = CpSessionStore.loadRun().armed
    @State private var cpLocation = CpSessionStore.loadLocation()
    @State private var cpAlerts = CpSessionStore.loadAlertPrefs()
    @State private var entityNames: [String: String] = [:]   // entity_id → friendly name, for display
    let onChange: (HaConfig) -> Void

    init(config: HaConfig, onChange: @escaping (HaConfig) -> Void) {
        _config = State(initialValue: config)
        self.onChange = onChange
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Home Assistant") {
                    LabeledContent("Server", value: prettyHost(config.baseUrl))
                    LabeledContent("Account", value: config.isSignedIn ? "Signed in" : "Long-lived token")
                }

                Section {
                    entityRow("Alarm panel", domain: "alarm_control_panel", allowNone: false,
                              selection: config.entityId) { e in apply { $0.entityId = e.id } }
                    entityRow("Front door", domain: "lock", allowNone: true,
                              selection: config.lockId) { e in
                        apply { $0.lockId = e.id; $0.lockName = e.id.isEmpty ? "" : e.name }
                    }
                    Picker("Disarm & unlock", selection: confirmBinding) {
                        Text("Face ID / passcode").tag(CONFIRM_BIOMETRIC)
                        Text("Confirm dialog").tag(CONFIRM_DIALOG)
                    }
                } header: {
                    Text("Alarm")
                } footer: {
                    Text("The panel the Alarm arms/disarms, an optional front-door lock, and how Disarm/Unlock are confirmed.")
                }

                Section {
                    entityRow("Thermostat", domain: "climate", allowNone: true,
                              selection: config.climateId) { e in apply { $0.climateId = e.id } }
                    entityRow("Resume button", domain: "button", allowNone: true,
                              selection: config.resumeId) { e in apply { $0.resumeId = e.id } }
                    NavigationLink {
                        MultiEntityPickerView(config: config, domains: ["sensor", "binary_sensor"],
                                              title: "Room sensors", selected: config.sensorIds) { ids in
                            apply { $0.sensorsJson = encodeIds(ids) }
                        }
                    } label: {
                        LabeledContent("Room sensors",
                                       value: config.sensorIds.isEmpty ? "None" : "\(config.sensorIds.count) selected")
                    }
                } header: {
                    Text("Thermostat")
                } footer: {
                    Text("The climate entity the Thermostat controls, an optional Resume button, and room sensors to show.")
                }
                Section {
                    if cpSignedIn {
                        LabeledContent("Account", value: cpAccountName())
                        NavigationLink {
                            CpLocationSearchView(onPicked: { cpLocation = CpSessionStore.loadLocation() })
                        } label: {
                            LabeledContent("Location",
                                           value: cpLocation.map { "\($0.title) · \($0.deviceIds.count) chargers" } ?? "Not set")
                        }
                        if cpLocation != nil {
                            TextField("Name (optional)", text: Binding(
                                get: { cpLocation?.label ?? "" },
                                set: { newLabel in
                                    guard let loc = cpLocation else { return }
                                    let updated = CpLocation(name: loc.name, address: loc.address, deviceIds: loc.deviceIds,
                                                             bounds: loc.bounds, city: loc.city, state: loc.state, label: newLabel)
                                    CpSessionStore.saveLocation(updated); cpLocation = updated
                                }))
                        }
                        Toggle("Auto-waitlist", isOn: Binding(
                            get: { cpAuto },
                            set: { on in
                                let run = CpSessionStore.loadRun()
                                let next = on ? cpResumeRun(run, nil, Int64(Date().timeIntervalSince1970 * 1000))
                                              : cpPauseRun(run)
                                CpSessionStore.saveRun(next); cpAuto = on
                                if on { CpNotify.requestPermission() }
                                WidgetCenter.shared.reloadAllTimelines()
                            }))
                        if cpAuto {
                            Toggle("Alert · Your turn", isOn: Binding(
                                get: { cpAlerts.offer },
                                set: { cpAlerts.offer = $0; CpSessionStore.setAlert("offer", $0) }))
                            Toggle("Alert · Accepted & held", isOn: Binding(
                                get: { cpAlerts.accepted },
                                set: { cpAlerts.accepted = $0; CpSessionStore.setAlert("accepted", $0) }))
                            Toggle("Alert · Snoozed", isOn: Binding(
                                get: { cpAlerts.snoozed },
                                set: { cpAlerts.snoozed = $0; CpSessionStore.setAlert("snoozed", $0) }))
                            Toggle("Alert · Second offer", isOn: Binding(
                                get: { cpAlerts.second },
                                set: { cpAlerts.second = $0; CpSessionStore.setAlert("second", $0) }))
                            Text("Drive now, a failed action, and signed-out always notify — these can't be turned off.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Button("Sign out of ChargePoint", role: .destructive) {
                            CpSessionStore.clear(); cpSignedIn = false; cpAuto = false
                            WidgetCenter.shared.reloadAllTimelines()
                        }
                    } else {
                        NavigationLink("Sign in to ChargePoint") {
                            CpSignInView(onSignedIn: { cpSignedIn = CpSessionStore.load().isSignedIn })
                        }
                    }
                } header: {
                    Text("ChargePoint")
                } footer: {
                    Text("A separate account (not Home Assistant). Auto-waitlist arms the auto-accept/snooze engine; iOS runs it best-effort on refresh (see docs/CHARGEPOINT-IOS.md).")
                }
                Section {
                    NavigationLink {
                        MultiEntityPickerView(config: config, domains: ["light"], title: "Always show",
                                              selected: config.lightPins.sorted()) { ids in
                            apply { $0.lightPinsJson = encodeIds(ids) }
                        }
                    } label: {
                        LabeledContent("Always show",
                                       value: config.lightPins.isEmpty ? "None" : "\(config.lightPins.count) selected")
                    }
                } header: {
                    Text("Lights")
                } footer: {
                    Text("Lights to always show on the Lights widget, so you can switch them on even when they're off.")
                }
                Section {
                    NavigationLink {
                        MultiEntityPickerView(config: config, domains: ["script"], title: "Scripts",
                                              selected: config.scriptIds) { ids in
                            apply { $0.scriptIdsJson = encodeIds(Array(ids.prefix(6))) }
                        }
                    } label: {
                        LabeledContent("Scripts", value: config.scriptIds.isEmpty ? "None" : "\(config.scriptIds.count) selected")
                    }
                } header: {
                    Text("Quick")
                } footer: {
                    Text("Up to 6 scripts or scenes to run from the Quick widget.")
                }
                Section {
                    NavigationLink {
                        MultiEntityPickerView(config: config,
                                              domains: ["switch", "light", "fan", "input_boolean", "script"],
                                              title: "Tiles", selected: config.favouriteIds) { ids in
                            apply { $0.favouriteIdsJson = encodeIds(Array(ids.prefix(12))) }
                        }
                    } label: {
                        LabeledContent("Tiles", value: config.favouriteIds.isEmpty ? "None" : "\(config.favouriteIds.count) selected")
                    }
                } header: {
                    Text("Favourites")
                } footer: {
                    Text("Up to 12 switches, lights, fans or scripts for the Favourites widget.")
                }
                Section {
                    NavigationLink {
                        MultiEntityPickerView(config: config, domains: ["cover", "binary_sensor", "lock"],
                                              title: "Doors", selected: config.doorIds) { ids in
                            apply { $0.doorIdsJson = encodeIds(ids) }
                        }
                    } label: {
                        LabeledContent("Doors", value: config.doorIds.isEmpty ? "None" : "\(config.doorIds.count) selected")
                    }
                } header: {
                    Text("Doors")
                } footer: {
                    Text("Doors, garages and window sensors for the Doors widget. Opening the garage asks for Face ID.")
                }
            }
            .navigationTitle("Settings")
            .task { await loadNames() }
        }
    }

    private var confirmBinding: Binding<String> {
        Binding(get: { config.confirmWith }, set: { v in apply { $0.confirmWith = v } })
    }

    @ViewBuilder
    private func entityRow(_ title: String, domain: String, allowNone: Bool,
                           selection: String, onPick: @escaping (HaEntity) -> Void) -> some View {
        NavigationLink {
            EntityPickerView(config: config, domain: domain, title: title,
                             allowNone: allowNone, selected: selection, onPick: onPick)
        } label: {
            LabeledContent(title, value: selection.isEmpty ? "Not set" : (entityNames[selection] ?? selection))
        }
    }

    /// Resolve entity_id → friendly name once (from `/api/states`), so the single-entity rows show
    /// human-readable names instead of raw ids. Falls back to the id when unknown or offline.
    private func loadNames() async {
        guard config.isSignedIn, entityNames.isEmpty,
              let json = try? await HaClient(config).allStatesJson() else { return }
        entityNames = Dictionary(parseEntities(json).map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
    }

    /// Immutable update: copy the config, set the field on the copy, persist, reload widgets.
    private func apply(_ mutate: (inout HaConfig) -> Void) {
        var next = config
        mutate(&next)
        config = next
        HaConfigStore.save(next)
        WidgetCenter.shared.reloadAllTimelines()
        onChange(next)
    }

    private func encodeIds(_ ids: [String]) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: ids),
              let s = String(data: data, encoding: .utf8) else { return "[]" }
        return s
    }

    private func prettyHost(_ url: String) -> String { URL(string: url)?.host ?? url }

    private func cpAccountName() -> String {
        let local = CpSessionStore.load().email.split(separator: "@").first.map(String.init) ?? ""
        return local.isEmpty ? "Signed in" : local
    }
}
