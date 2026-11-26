import SwiftUI
import HearthKit

/// HA-only entity controls; field edits retain the account scope captured when this view opens.
@MainActor
struct HaSettingsSections: View {
    @State private var config: HaConfig
    @State private var editScope: String?
    @State private var entityNames: [String: String] = [:]
    @State private var saveError: String?
    let runtime: any SettingsRuntime
    let onChange: (HaConfig) -> Void

    init(config: HaConfig, runtime: any SettingsRuntime = LiveSettingsRuntime.shared,
         onChange: @escaping (HaConfig) -> Void) {
        _config = State(initialValue: config)
        self.runtime = runtime
        let current = runtime.loadHa()
        _editScope = State(initialValue: haSameConnection(current?.config, config) ? current?.scope : nil)
        self.onChange = onChange
    }

    var body: some View {
        Group {
            Section("Home Assistant") {
                LabeledContent("Server", value: prettyHost(config.baseUrl))
                LabeledContent("Account", value: config.isSignedIn ? "Signed in" : "Long-lived token")
            }
            .task { synchronizeConfig(); await loadNames() }
            .onAppear { synchronizeConfig() }
            .alert("Couldn't save settings", isPresented: Binding(
                get: { saveError != nil }, set: { if !$0 { saveError = nil } }
            )) { Button("OK", role: .cancel) {} } message: { Text(saveError ?? "") }

            Section {
                entityRow("Alarm panel", domain: "alarm_control_panel", allowNone: true,
                          selection: config.entityId) { e in try apply { $0.entityId = e.id } }
                entityRow("Front door", domain: "lock", allowNone: true,
                          selection: config.lockId) { e in
                    try apply { $0.lockId = e.id; $0.lockName = e.id.isEmpty ? "" : e.name }
                }
            } header: {
                Text("Alarm")
            } footer: {
                Text("Alarm panel and front-door lock are optional. Choose the entities you want the Alarm widget to use.")
            }

            Section {
                entityRow("Thermostat", domain: "climate", allowNone: true,
                          selection: config.climateId) { e in try apply { $0.climateId = e.id } }
                entityRow("Resume button", domain: "button", allowNone: true,
                          selection: config.resumeId) { e in try apply { $0.resumeId = e.id } }
                NavigationLink {
                    MultiEntityPickerView(config: config, domains: ["sensor", "binary_sensor"],
                                          title: "Room sensors", selected: config.sensorIds, runtime: runtime) { ids in
                        try apply { $0.sensorsJson = encodeIds(ids) }
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
                NavigationLink {
                    MultiEntityPickerView(config: config, domains: ["light"], title: "Always show",
                                          selected: config.lightPins.sorted(), runtime: runtime) { ids in
                        try apply { $0.lightPinsJson = encodeIds(ids) }
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
                                              selected: config.scriptIds, limit: 6, runtime: runtime) { ids in
                            try apply { $0.scriptIdsJson = encodeIds(ids) }
                    }
                } label: {
                    LabeledContent("Scripts", value: config.scriptIds.isEmpty ? "None" : "\(config.scriptIds.count) selected")
                }
            } header: {
                Text("Quick")
            } footer: {
                Text("Up to 6 scripts to run from the Quick widget.")
            }
            Section {
                NavigationLink {
                    MultiEntityPickerView(config: config,
                                          domains: ["switch", "light", "fan", "input_boolean", "script"],
                                              title: "Tiles", selected: config.favouriteIds, limit: 12, runtime: runtime) { ids in
                            try apply { $0.favouriteIdsJson = encodeIds(ids) }
                    }
                } label: {
                    LabeledContent("Tiles", value: config.favouriteIds.isEmpty ? "None" : "\(config.favouriteIds.count) selected")
                }
            } header: {
                Text("Favourites")
            } footer: {
                Text("Up to 12 switches, lights, fans, toggle helpers or scripts for the Favourites widget.")
            }
            Section {
                NavigationLink {
                    MultiEntityPickerView(config: config, domains: ["cover", "binary_sensor", "lock"],
                                          title: "Doors", selected: config.doorIds, doorsOnly: true, runtime: runtime) { ids in
                        try apply { $0.doorIdsJson = encodeIds(ids); $0.doorsChosen = true }
                    }
                } label: {
                    LabeledContent("Doors", value: config.doorIds.isEmpty ? "None" : "\(config.doorIds.count) selected")
                }
            } header: {
                Text("Doors")
            } footer: {
                Text("Doors, garages and window sensors for the Doors widget. Garage controls work with one tap.")
            }
        }
    }

    @ViewBuilder
    private func entityRow(_ title: String, domain: String, allowNone: Bool,
                           selection: String, onPick: @escaping (HaEntity) throws -> Void) -> some View {
        NavigationLink {
            EntityPickerView(config: config, domain: domain, title: title,
                             allowNone: allowNone, selected: selection, runtime: runtime, onPick: onPick)
        } label: {
            LabeledContent(title, value: selection.isEmpty ? "Not set" : (entityNames[selection] ?? selection))
        }
    }

    /// Resolve entity_id → friendly name once (from `/api/states`), so the single-entity rows show
    /// human-readable names instead of raw ids. Falls back to the id when unknown or offline.
    private func loadNames() async {
        guard config.hasAuth, entityNames.isEmpty,
              let discovery = try? await runtime.discoverHa(config: config, scope: editScope,
                                                            purpose: .names) else { return }
        entityNames = Dictionary(discovery.entities.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
    }

    private func synchronizeConfig() {
        guard let current = runtime.loadHa(), current.scope == editScope,
              let latest = current.config, haSameConnection(config, latest) else { return }
        config = latest
        onChange(latest)
    }

    /// Apply one field edit to the current account's persisted configuration atomically.
    private func apply(_ mutate: @escaping (inout HaConfig) -> Void) throws {
        guard let editScope,
              let next = try runtime.saveHaEdit(expectedScope: editScope, edit: .fields(mutate)) else {
            throw HaError("Your account changed. Reopen Settings to continue.")
        }
        config = next
        runtime.refreshWidgets(kinds: [])
        onChange(next)
    }

    private func encodeIds(_ ids: [String]) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: ids),
              let s = String(data: data, encoding: .utf8) else { return "[]" }
        return s
    }

    private func prettyHost(_ url: String) -> String { URL(string: url)?.host ?? url }

}
