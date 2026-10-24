import SwiftUI
import WidgetKit
import HearthKit

@main
struct HearthApp: App {
    var body: some Scene {
        WindowGroup { ContentView() }
    }
}

/// Two tabs: **Live** reads the signed-in `HaConfig` (shared with the widget via the App Group) and
/// shows the real car — or the Home Assistant sign-in when not yet connected. **Preview** is the
/// original verification gallery that renders every Beacon at the medium-widget size.
struct ContentView: View {
    @State private var config: HaConfig? = HaConfigStore.load()
    @State private var selection = ContentView.initialTab()
    @ObservedObject private var gate = AlarmGate.shared
    @ObservedObject private var climateGate = ClimateGate.shared
    @ObservedObject private var garageGate = GarageGate.shared
    @ObservedObject private var joinGate = CpJoinGate.shared
    @ObservedObject private var snoozeGate = CpSnoozeGate.shared

    var body: some View {
        TabView(selection: $selection) {
            liveTab
                .tabItem { Label("Live", systemImage: "car.fill") }
                .tag(0)
            settingsTab
                .tabItem { Label("Settings", systemImage: "gearshape.fill") }
                .tag(1)
            WidgetGalleryView()
                .tabItem { Label("Preview", systemImage: "square.grid.2x2.fill") }
                .tag(2)
        }
        .alert("Confirm", isPresented: Binding(
            get: { gate.confirming != nil },
            set: { if !$0 { gate.cancel() } }
        ), presenting: gate.confirming) { action in
            Button(action.verb, role: .destructive) { gate.confirm(action) }
            Button("Cancel", role: .cancel) { gate.cancel() }
        } message: { action in Text(action.title) }
        .confirmationDialog(climateGate.pick?.title ?? "", isPresented: Binding(
            get: { climateGate.pick != nil },
            set: { if !$0 { climateGate.dismiss() } }
        ), titleVisibility: .visible, presenting: climateGate.pick) { pick in
            ForEach(pick.options, id: \.self) { opt in
                Button(opt.capitalized) { climateGate.choose(pick.kind, opt) }
            }
            Button("Cancel", role: .cancel) { climateGate.dismiss() }
        }
        .alert("Open the garage?", isPresented: Binding(
            get: { garageGate.confirming != nil },
            set: { if !$0 { garageGate.cancel() } }
        ), presenting: garageGate.confirming) { id in
            Button("Open", role: .destructive) { garageGate.confirm(id) }
            Button("Cancel", role: .cancel) { garageGate.cancel() }
        }
        .confirmationDialog("Join the ChargePoint waitlist?", isPresented: Binding(
            get: { joinGate.asking },
            set: { if !$0 { joinGate.cancel() } }
        ), titleVisibility: .visible) {
            Button("Join & auto-run") { joinGate.join(auto: true) }
            Button("Just join") { joinGate.join(auto: false) }
            Button("Cancel", role: .cancel) { joinGate.cancel() }
        }
        .confirmationDialog("Snooze for…", isPresented: Binding(
            get: { snoozeGate.asking },
            set: { if !$0 { snoozeGate.cancel() } }
        ), titleVisibility: .visible) {
            Button("10 minutes") { snoozeGate.snooze(minutes: 10) }
            Button("30 minutes") { snoozeGate.snooze(minutes: 30) }
            Button("60 minutes") { snoozeGate.snooze(minutes: 60) }
            Button("Cancel", role: .cancel) { snoozeGate.cancel() }
        }
    }

    /// Initial tab from a launch arg (`-tab live|settings|preview`), for screenshots and testing.
    private static func initialTab() -> Int {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-tab"), i + 1 < args.count else { return 0 }
        switch args[i + 1] { case "settings": return 1; case "preview": return 2; default: return 0 }
    }

    @ViewBuilder private var liveTab: some View {
        if let config, config.carReady {
            LiveDashboardView(config: config, onSignOut: signOut)
        } else {
            SignInView(onSignedIn: { config = HaConfigStore.load() })
        }
    }

    @ViewBuilder private var settingsTab: some View {
        if let c = config, c.hasAuth {
            SettingsView(config: c, onChange: { config = $0 })
        } else {
            ContentUnavailableView("Sign in first", systemImage: "gearshape",
                description: Text("Connect to Home Assistant on the Live tab to configure widgets."))
        }
    }

    private func signOut() {
        HaConfigStore.clear()
        Task { await HaAuth.shared.forget() }
        WidgetCenter.shared.reloadAllTimelines()
        config = nil
    }
}
