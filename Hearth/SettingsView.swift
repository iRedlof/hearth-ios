import SwiftUI
import HearthKit

/// Each provider has independent setup and account ownership. Settings itself is always available.
@MainActor
struct SettingsView: View {
    @State private var config: HaConfig?
    @State private var connectingHa = false
    @State private var signOutError: String?
    let runtime: any SettingsRuntime
    let onChange: (HaConfig?) -> Void

    init(config: HaConfig?, runtime: any SettingsRuntime = LiveSettingsRuntime.shared,
         onChange: @escaping (HaConfig?) -> Void) {
        _config = State(initialValue: config)
        self.runtime = runtime
        self.onChange = onChange
    }

    var body: some View {
        NavigationStack {
            Form {
                if let config, haSettingsReady(config) {
                    HaSettingsSections(config: config, runtime: runtime) { next in
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
                CpSettingsSection(runtime: runtime)
            }
            .navigationTitle("Settings")
            .accessibilityIdentifier("settings.root")
            .sheet(isPresented: $connectingHa) {
                NavigationStack {
                    SettingsSetupScreen(route: .haSignIn, runtime: runtime, initialURL: config?.baseUrl) {
                        config = runtime.loadHa()?.config
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
            config = try runtime.saveHaEdit(expectedScope: runtime.loadHa()?.scope, edit: .signOut)
            runtime.refreshWidgets(kinds: [])
            onChange(config)
        } catch { signOutError = friendlyError(error) }
    }
}
