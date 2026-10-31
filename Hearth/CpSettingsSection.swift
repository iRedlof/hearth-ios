import SwiftUI
import HearthKit

/// ChargePoint is an independent integration; it never requires a Home Assistant configuration.
@MainActor
struct CpSettingsSection: View {
    let runtime: any SettingsRuntime
    @State private var cp: SettingsCpState
    @State private var editError: String?

    init(runtime: any SettingsRuntime = LiveSettingsRuntime.shared) {
        self.runtime = runtime
        _cp = State(initialValue: runtime.loadCp())
    }

    var body: some View {
        Section {
            if cp.session.isSignedIn {
                LabeledContent("Account", value: cp.accountName)
                    .accessibilityIdentifier("settings.cp.account")
                NavigationLink {
                    SettingsSetupScreen(route: .cpLocation, runtime: runtime) { cp = runtime.loadCp() }
                } label: {
                    LabeledContent("Location",
                                   value: cp.location.map { "\($0.title) · \($0.deviceIds.count) chargers" } ?? "Not set")
                }
                .accessibilityIdentifier("settings.cp.location")
                if cp.location != nil {
                    TextField("Name (optional)", text: Binding(
                        get: { cp.location?.label ?? "" },
                        set: { perform(.locationName($0)) }))
                }
                Toggle("Auto-waitlist", isOn: Binding(
                    get: { cp.auto },
                    set: { perform(.auto($0)) }))
                if cp.auto {
                    Toggle("Alert · Your turn", isOn: Binding(
                        get: { cp.alerts.offer },
                        set: { perform(.alert("offer", $0)) }))
                    Toggle("Alert · Accepted & held", isOn: Binding(
                        get: { cp.alerts.accepted },
                        set: { perform(.alert("accepted", $0)) }))
                    Toggle("Alert · Snoozed", isOn: Binding(
                        get: { cp.alerts.snoozed },
                        set: { perform(.alert("snoozed", $0)) }))
                    Toggle("Alert · Second offer", isOn: Binding(
                        get: { cp.alerts.second },
                        set: { perform(.alert("second", $0)) }))
                    Text("Drive now, a failed action, and signed-out always notify — these can't be turned off.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Button("Sign out of ChargePoint", role: .destructive) { perform(.signOut) }
            } else {
                NavigationLink("Sign in to ChargePoint") {
                    SettingsSetupScreen(route: .cpSignIn, runtime: runtime) { cp = runtime.loadCp() }
                }
                .accessibilityIdentifier("settings.cp.account")
            }
        } header: {
            Text("ChargePoint")
        } footer: {
            Text("A separate account (not Home Assistant). Auto-waitlist accepts and snoozes offers automatically. On iOS, it runs when the widget refreshes.")
        }
        .onAppear { cp = runtime.loadCp() }
        .alert("Couldn't update ChargePoint", isPresented: Binding(
            get: { editError != nil }, set: { if !$0 { editError = nil } }
        )) { Button("OK", role: .cancel) {} } message: { Text(editError ?? "") }
    }

    private func perform(_ edit: SettingsCpEdit) {
        Task { @MainActor in
            do { cp = try await runtime.performCpEdit(edit) }
            catch is CancellationError { return }
            catch { editError = friendlyError(error) }
        }
    }
}
