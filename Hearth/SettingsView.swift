import SwiftUI
import WidgetKit
import HearthKit

/// App settings — the single shared `HaConfig` every widget reads (matching Android's one
/// global config). Slice 1 ports the **Alarm** entity picker; door / climate / confirm-mode /
/// room-sensors follow in later slices.
///
/// Every change builds a *new* `HaConfig` (value-type copy — never mutate the live one),
/// persists it to the App-Group store, and reloads all widget timelines so the home-screen
/// widgets immediately pick up the change.
struct SettingsView: View {
    @State private var config: HaConfig
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
                    pickerRow(title: "Alarm panel", domain: "alarm_control_panel",
                              allowNone: false, selection: config.entityId) { picked in
                        apply { $0.entityId = picked }
                    }
                } header: {
                    Text("Alarm")
                } footer: {
                    Text("The alarm_control_panel the Alarm widget arms, disarms and shows.")
                }
                Section {
                    pickerRow(title: "Thermostat", domain: "climate",
                              allowNone: true, selection: config.climateId) { picked in
                        apply { $0.climateId = picked }
                    }
                } header: {
                    Text("Thermostat")
                } footer: {
                    Text("The climate entity the Thermostat widget shows and controls.")
                }
            }
            .navigationTitle("Settings")
        }
    }

    @ViewBuilder
    private func pickerRow(title: String, domain: String, allowNone: Bool,
                           selection: String, onPick: @escaping (String) -> Void) -> some View {
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

    private func prettyHost(_ url: String) -> String { URL(string: url)?.host ?? url }
}
