import SwiftUI
import WidgetKit
import HearthKit

/// Each provider has independent setup and account ownership. Settings itself is always available.
struct SettingsView: View {
    @State private var config: HaConfig?
    @State private var connectingHa = false
    @State private var signOutError: String?
    let onChange: (HaConfig?) -> Void

    init(config: HaConfig?, onChange: @escaping (HaConfig?) -> Void) {
        _config = State(initialValue: config)
        self.onChange = onChange
    }

    var body: some View {
        NavigationStack {
            Form {
                if let config, haSettingsReady(config) {
                    HaSettingsSections(config: config) { next in
                        self.config = next
                        onChange(next)
                    }
                    Section {
                        Button("Sign out of Home Assistant", role: .destructive, action: signOutHa)
                    }
                } else {
                    Section {
                        Button("Connect Home Assistant") { connectingHa = true }
                            .accessibilityIdentifier("settings.ha.connect")
                    } header: {
                        Text("Home Assistant")
                    } footer: {
                        Text("Connect to configure your home widgets. ChargePoint uses its own account.")
                    }
                }
                CpSettingsSection()
            }
            .navigationTitle("Settings")
            .accessibilityIdentifier("settings.root")
            .sheet(isPresented: $connectingHa) {
                NavigationStack {
                    SignInView(initialURL: config?.baseUrl) {
                        config = HaConfigStore.load()
                        onChange(config)
                        connectingHa = false
                    }
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancel") { connectingHa = false }
                        }
                    }
                }
            }
            .alert("Couldn't sign out", isPresented: Binding(
                get: { signOutError != nil }, set: { if !$0 { signOutError = nil } }
            )) { Button("OK", role: .cancel) {} } message: { Text(signOutError ?? "") }
        }
    }

    private func signOutHa() {
        do {
            try HaConfigStore.clear()
            Task { await HaAuth.shared.forget() }
            WidgetCenter.shared.reloadAllTimelines()
            config = nil
            onChange(nil)
        } catch { signOutError = friendlyError(error) }
    }
}
