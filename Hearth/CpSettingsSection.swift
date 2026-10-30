import SwiftUI
import WidgetKit
import HearthKit

/// ChargePoint is an independent integration; it never requires a Home Assistant configuration.
struct CpSettingsSection: View {
    @State private var cpSignedIn = CpSessionStore.load().isSignedIn
    @State private var cpAuto = CpSessionStore.loadRun().armed
    @State private var cpLocation = CpSessionStore.loadLocation()
    @State private var cpAlerts = CpSessionStore.loadAlertPrefs()

    var body: some View {
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
                        Task { @MainActor in
                            if on { await CpWidgetOperation.enableAuto() }
                            else { CpSessionStore.saveRun(cpPauseRun(CpSessionStore.loadRun())) }
                            cpAuto = CpSessionStore.loadRun().armed
                            if cpAuto { CpNotify.requestPermission() }
                            CpWidgetOperation.reload()
                        }
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
            Text("A separate account (not Home Assistant). Auto-waitlist accepts and snoozes offers automatically. On iOS, it runs when the widget refreshes.")
        }
    }

    private func cpAccountName() -> String {
        let local = CpSessionStore.load().email.split(separator: "@").first.map(String.init) ?? ""
        return local.isEmpty ? "Signed in" : local
    }
}
