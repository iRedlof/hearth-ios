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
            }
            .navigationTitle("Settings")
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
            LabeledContent(title, value: selection.isEmpty ? "Not set" : selection)
        }
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
