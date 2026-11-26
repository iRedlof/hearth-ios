import SwiftUI
import HearthKit

/// ChargePoint is an independent integration; it never requires a Home Assistant configuration.
@MainActor
struct CpSettingsSection: View {
    let runtime: any SettingsRuntime
    @State private var cp: SettingsCpState
    @State private var editError: String?
    @State private var editID = UUID()
    @State private var nameDraft: String
    @State private var nameOrigin: CpSettingsOrigin?
    @FocusState private var nameFocused: Bool

    init(runtime: any SettingsRuntime = LiveSettingsRuntime.shared) {
        self.runtime = runtime
        let initial = runtime.loadCp()
        _cp = State(initialValue: initial)
        _nameDraft = State(initialValue: initial.location?.label ?? "")
    }

    var body: some View {
        Section {
            if cp.session.isSignedIn {
                LabeledContent("Account", value: cp.accountName)
                    .accessibilityIdentifier("settings.cp.account")
                NavigationLink {
                    SettingsSetupScreen(route: .cpLocation, runtime: runtime, cpOrigin: cp.origin) { cp = runtime.loadCp() }
                } label: {
                    LabeledContent("Location",
                                   value: cp.location.map { "\($0.title) · \($0.deviceIds.count) chargers" } ?? "Not set")
                }
                .accessibilityIdentifier("settings.cp.location")
                if cp.location != nil {
                    TextField("Name (optional)", text: $nameDraft)
                        .focused($nameFocused)
                        .onSubmit { nameFocused = false }
                        .onChange(of: nameFocused) { _, editing in
                            if editing { nameOrigin = cp.origin } else { saveName() }
                        }
                }
                Toggle("Auto-waitlist", isOn: Binding(
                    get: { cp.auto },
                    set: { on in
                        perform(.auto(on ? (cp.autoControl == .join ? .join : .resume) : .pause, cp.renderedOrigin))
                    }))
                    .disabled(!cp.auto && (cp.autoControl == .disabled || cp.renderedOrigin == nil))
                if !cp.auto, cp.autoControl == .join {
                    Text("Turning on joins this location's waitlist and starts Auto.")
                        .font(.caption).foregroundStyle(.secondary)
                } else if !cp.auto, cp.autoControl == .resume {
                    Text("Turning on resumes Auto for your current place in line.")
                        .font(.caption).foregroundStyle(.secondary)
                }
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
                NavigationLink(cp.unavailable ? "ChargePoint unavailable" : "Sign in to ChargePoint") {
                    SettingsSetupScreen(route: .cpSignIn, runtime: runtime, cpOrigin: cp.origin) { cp = runtime.loadCp() }
                }
                .accessibilityIdentifier("settings.cp.account")
                if cp.auto {
                    Text("Auto is on · Sign in to continue").foregroundStyle(.secondary)
                    Button("Stop Auto") { perform(.auto(.pause, cp.renderedOrigin)) }
                }
                if cp.unavailable {
                    Text("Shared storage unavailable · Open sign in to recover.").foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("ChargePoint")
        } footer: {
            Text("A separate account (not Home Assistant). Auto-waitlist accepts and snoozes offers automatically. On iOS, it runs when the widget refreshes.")
        }
        .onAppear { editID = UUID(); cp = runtime.loadCp(); nameDraft = cp.location?.label ?? "" }
        .alert("Couldn't update ChargePoint", isPresented: Binding(
            get: { editError != nil }, set: { if !$0 { editError = nil } }
        )) { Button("OK", role: .cancel) {} } message: { Text(editError ?? "") }
    }

    private func saveName() {
        guard nameDraft != cp.location?.label else { return }
        guard let origin = nameOrigin else { return }
        nameOrigin = nil
        perform(.locationName(nameDraft), expected: origin)
    }

    private func perform(_ edit: SettingsCpEdit, expected supplied: CpSettingsOrigin? = nil) {
        let expected = supplied ?? cp.origin
        let captured = UUID(); editID = captured
        Task { @MainActor in
            do {
                let result = try await runtime.performCpEdit(edit, expected: expected)
                guard editID == captured else { return }
                cp = result
            }
            catch is CancellationError { return }
            catch { if editID == captured { editError = friendlyError(error) } }
        }
    }
}
