import SwiftUI
import WidgetKit
import HearthKit

@main
struct HearthApp: App {
    #if DEBUG
    private let probeSelection: CarRouteProbeSelection
    #endif
    init() {
        #if DEBUG
        if CpSessionStore.fixtureActive {
            probeSelection = .inactive
            return
        }
        probeSelection = CarRouteProbe.resolveLaunch(arguments: ProcessInfo.processInfo.arguments)
        if case .inactive = probeSelection,
           Self.settingsFixture() == nil,
           ProcessInfo.processInfo.arguments.contains("-parityLive") { ParityCatalog.deactivateWidget() }
        #endif
    }
    var body: some Scene {
        WindowGroup {
            #if DEBUG
            if CpSessionStore.fixtureActive {
                CpOwnedNativeHost()
            } else {
            switch probeSelection {
            case .armed(let run): CarReadingsProbeHost(run: run)
            case .blocked(let reason): CarReadingsProbeBlockedHost(reason: reason)
            case .inactive:
                if let state = Self.carReadingsFixture() { CarReadingsFixtureHost(state: state) }
                else if let concept = Self.accessibleFixture() { AccessibleBeaconFixtureScreen(concept: concept) }
                else if let fixture = Self.settingsFixture() { SettingsFixtureScreen(fixture: fixture) }
                else if let id = Self.parityState() { ParityStateScreen(id: id) }
                else { ContentView() }
            }
            }
            #else
            if let id = Self.parityState() { ParityStateScreen(id: id) }
            else { ContentView() }
            #endif
        }
    }

    #if DEBUG
    private static func carReadingsFixture() -> String? {
        let args = ProcessInfo.processInfo.arguments
        guard let index = args.firstIndex(of: "-carRouteFixture"), index + 1 < args.count else { return nil }
        return args[index + 1]
    }

    private static func accessibleFixture() -> AccessibleBeaconConcept? {
        let args = ProcessInfo.processInfo.arguments
        guard let index = args.firstIndex(of: "-accessibleFixture"), index + 1 < args.count else { return nil }
        return AccessibleBeaconConceptCatalog.concept(args[index + 1])
    }

    private static func settingsFixture() -> SettingsFixtureCase? {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-settingsFixture") else { return nil }
        guard i + 1 < args.count else { return .fresh }
        // An invalid debug selector still stays on the inert branch.
        return SettingsFixtureCase(rawValue: args[i + 1]) ?? .fresh
    }
    #endif

    /// `-parityState <id>` renders a single Beacon state full-screen for the parity-gallery
    /// screenshot script (docs/parity-comparison). No effect in normal use.
    private static func parityState() -> String? {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-parityState"), i + 1 < args.count else { return nil }
        return args[i + 1]
    }
}

/// Two tabs: **Live** reads the signed-in `HaConfig` (shared with the widget via the App Group) and
/// shows the real car — or the Home Assistant sign-in when not yet connected. **Preview** is the
/// original verification gallery that renders every Beacon at the medium-widget size.
struct ContentView: View {
    @State private var config: HaConfig?
    @State private var selection = ContentView.initialTab()
    @ObservedObject private var climateGate = ClimateGate.shared
    @ObservedObject private var garageGate = GarageGate.shared
    @ObservedObject private var cpSetup = CpSetupGate.shared
    @ObservedObject private var haSetup = HaSetupGate.shared
    @ObservedObject private var carReadings = CarReadingsGate.shared
    @State private var presentedSheet: HearthSheet?
    @State private var settingsCarReturn: CarReadingsRequest?
    @State private var signOutError: String?
    private let carReadingsRuntime: CarReadingsRuntime
    private let inertTabs: Bool

    init(carReadingsRuntime: CarReadingsRuntime? = nil, inertTabs: Bool = false) {
        self.carReadingsRuntime = carReadingsRuntime
            ?? (inertTabs ? CarReadingsRuntime(tickets: nil, state: nil) : .live)
        self.inertTabs = inertTabs
        _config = State(initialValue: inertTabs ? nil : HaConfigStore.load())
    }

    var body: some View {
        TabView(selection: $selection) {
            liveTab
                .tabItem { Label("Live", systemImage: "car.fill") }
                .tag(0)
            settingsTab
                .tabItem { Label("Settings", systemImage: "gearshape.fill") }
                .tag(1)
            previewTab
                .tabItem { Label("Preview", systemImage: "square.grid.2x2.fill") }
                .tag(2)
        }
        .alert("Couldn't sign out", isPresented: Binding(
            get: { signOutError != nil }, set: { if !$0 { signOutError = nil } }
        )) { Button("OK", role: .cancel) {} } message: { Text(signOutError ?? "") }
        .confirmationDialog(climateGate.pick?.title ?? "", isPresented: Binding(
            get: { !inertTabs && climateGate.pick != nil },
            set: { if !inertTabs && !$0 { climateGate.dismiss() } }
        ), titleVisibility: .visible, presenting: climateGate.pick) { pick in
            ForEach(pick.options, id: \.self) { opt in
                Button(opt.capitalized) { if !inertTabs { climateGate.choose(pick, opt) } }
            }
            Button("Cancel", role: .cancel) { if !inertTabs { climateGate.dismiss() } }
        }
        .alert("Thermostat", isPresented: Binding(
            get: { !inertTabs && climateGate.error != nil }, set: { if !inertTabs && !$0 { climateGate.error = nil } }
        )) {
            Button("OK") { if !inertTabs { climateGate.error = nil } }
        } message: { Text(climateGate.error ?? "") }
        .alert("Open the garage?", isPresented: Binding(
            get: { !inertTabs && garageGate.confirming != nil },
            set: { if !inertTabs && !$0 { garageGate.cancel() } }
        ), presenting: garageGate.confirming) { id in
            Button("Open", role: .destructive) { if !inertTabs { garageGate.confirm(id) } }
            Button("Cancel", role: .cancel) { if !inertTabs { garageGate.cancel() } }
        }
        .onChange(of: cpSetup.route, initial: true) {
            guard let route = cpSetup.route else { return }
            cpSetup.route = nil
            settingsCarReturn = nil
            presentedSheet = .chargepoint(route, UUID())
        }
        .onChange(of: carReadings.request, initial: true) {
            guard let request = carReadings.request else { return }
            carReadings.request = nil
            presentCarReadings(request)
        }
        .onOpenURL { url in
            guard let destination = carReadingsDestination(from: url) else { return }
            let request = CarReadingsRequest(destination: destination)
            #if DEBUG
            var fields = ["requestID": request.id.uuidString, "destination": "unavailable"]
            if case .ticket(let id) = destination {
                fields["destination"] = "ticket"
                fields["ticketID"] = id.uuidString
            }
            carReadingsRuntime.probeReceipts?.record(phase: "sceneReceived", fields: fields)
            #endif
            presentCarReadings(request)
        }
        .onChange(of: haSetup.request, initial: true) {
            guard haSetup.request != nil else { return }
            haSetup.request = nil
            settingsCarReturn = nil
            if !inertTabs { config = HaConfigStore.load() }
            if haSetup.reconnect {
                presentedSheet = .reconnect(UUID(), returningTo: nil)
            } else {
                presentedSheet = nil
                selection = (inertTabs || config?.hasAuth == true) ? 1 : 0
            }
        }
        .sheet(item: $presentedSheet) { sheet in
            switch sheet {
            case .chargepoint(let route, _):
                NavigationStack {
                    if inertTabs {
                        ControlledSetupScreen(title: "Controlled ChargePoint setup",
                            onCancel: {
                                guard presentedSheet?.id == sheet.id else { return }
                                presentedSheet = nil
                            }, onComplete: {
                                guard presentedSheet?.id == sheet.id else { return }
                                presentedSheet = nil
                            })
                    } else if route == .signin {
                        CpSignInView(onSignedIn: {
                            guard presentedSheet?.id == sheet.id else { return }
                            presentedSheet = nil
                        })
                    } else {
                        CpLocationSearchView(onPicked: {
                            guard presentedSheet?.id == sheet.id else { return }
                            presentedSheet = nil
                        })
                    }
                }
                .id(sheet.id)
            case .reconnect(_, let original):
                NavigationStack {
                    if inertTabs {
                        ControlledSetupScreen(title: "Controlled Home Assistant reconnect",
                            onCancel: { finishReconnect(sheet, completed: false) },
                            onComplete: { finishReconnect(sheet, completed: true) })
                    } else {
                        SignInView(initialURL: config?.baseUrl) {
                            finishReconnect(sheet, completed: true)
                        }
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Cancel") { finishReconnect(sheet, completed: false) }
                            }
                        }
                    }
                }
                .id(sheet.id)
                .interactiveDismissDisabled(original != nil)
            case .car(let request):
                CarReadingsScreen(request: request, runtime: carReadingsRuntime,
                    onClose: {
                        guard presentedSheet?.id == sheet.id else { return }
                        presentedSheet = nil
                    },
                    onSettings: {
                        guard presentedSheet?.id == sheet.id else { return }
                        if !inertTabs { config = HaConfigStore.load() }
                        #if DEBUG
                        recordCarTransition("settingsStarted", original: request, transitionID: sheet.id)
                        #endif
                        settingsCarReturn = request
                        selection = 1
                        presentedSheet = nil
                    },
                    onReconnect: {
                        guard presentedSheet?.id == sheet.id else { return }
                        if !inertTabs { config = HaConfigStore.load() }
                        let reconnect = HearthSheet.reconnect(UUID(), returningTo: request)
                        #if DEBUG
                        recordCarTransition("reconnectStarted", original: request, transitionID: reconnect.id)
                        #endif
                        settingsCarReturn = nil
                        presentedSheet = reconnect
                    })
                .id(request.id)
            }
        }
    }

    /// URL delivery remains local to this scene; compatible intent delivery shares this sink.
    private func presentCarReadings(_ request: CarReadingsRequest) {
        guard request.destination != .inert else { return }
        settingsCarReturn = nil
        presentedSheet = .car(request)
    }

    private func finishReconnect(_ sheet: HearthSheet, completed: Bool) {
        guard presentedSheet?.id == sheet.id,
              case .reconnect(_, let original) = sheet else { return }
        if completed, !inertTabs { config = HaConfigStore.load() }
        if let original {
            let reopened = original.reopened()
            #if DEBUG
            recordCarTransition(completed ? "reconnectReturned" : "reconnectCancelled",
                original: original, reopened: reopened, transitionID: sheet.id)
            #endif
            presentCarReadings(reopened)
        } else {
            if completed { selection = 0 }
            presentedSheet = nil
        }
    }

    #if DEBUG
    /// Observes existing ownership decisions; it never chooses a destination or reads a store.
    private func recordCarTransition(_ phase: String, original: CarReadingsRequest,
                                     reopened: CarReadingsRequest? = nil, transitionID: String) {
        var fields = ["requestID": original.id.uuidString, "transitionID": transitionID,
                      "ticketID": original.ticketID?.uuidString ?? "unavailable"]
        if let reopened { fields["requestEventID"] = reopened.id.uuidString }
        carReadingsRuntime.probeReceipts?.record(phase: phase, fields: fields)
    }
    #endif

    /// Initial tab from a launch arg (`-tab live|settings|preview`), for screenshots and testing.
    private static func initialTab() -> Int {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-tab"), i + 1 < args.count else { return 0 }
        switch args[i + 1] { case "settings": return 1; case "preview": return 2; default: return 0 }
    }

    @ViewBuilder private var liveTab: some View {
        if inertTabs {
            Text("Controlled Car route fixture · Live tab")
        } else if let config, config.carReady {
            LiveDashboardView(config: config, onSignOut: signOut)
        } else {
            SignInView(onSignedIn: { config = HaConfigStore.load() })
        }
    }

    @ViewBuilder private var settingsTab: some View {
        Group {
            if inertTabs { Text("Controlled Car route fixture · Settings tab") }
            else {
                SettingsView(config: config, onChange: { config = $0 })
                    .id(HaConfigStore.requestScope())
            }
        }
        .safeAreaInset(edge: .top) {
            if let original = settingsCarReturn {
                Button {
                    guard settingsCarReturn?.id == original.id else { return }
                    let reopened = original.reopened()
                    #if DEBUG
                    recordCarTransition("settingsReturned", original: original, reopened: reopened,
                        transitionID: "car:\(original.id.uuidString)")
                    #endif
                    presentCarReadings(reopened)
                } label: {
                    Label("Back to car readings", systemImage: "car")
                        .font(.body.weight(.semibold))
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                }
                .padding(.horizontal)
                .background(.regularMaterial)
            }
        }
    }

    @ViewBuilder private var previewTab: some View {
        if inertTabs { Text("Controlled Car route fixture · Preview tab") }
        else { WidgetGalleryView() }
    }

    private func signOut() {
        do {
            try HaConfigStore.clear()
            Task { await HaAuth.shared.forget() }
            WidgetCenter.shared.reloadAllTimelines()
            config = nil
        } catch { signOutError = friendlyError(error) }
    }
}

private enum HearthSheet: Identifiable {
    case chargepoint(CpSetupRoute, UUID)
    case reconnect(UUID, returningTo: CarReadingsRequest?)
    case car(CarReadingsRequest)
    var id: String {
        switch self {
        case .chargepoint(_, let id): "chargepoint:\(id)"
        case .reconnect(let id, _): "reconnect:\(id)"
        case .car(let request): "car:\(request.id)"
        }
    }
}

/// Controlled setup transitions never create an authentication coordinator or touch real config.
private struct ControlledSetupScreen: View {
    let title: String
    let onCancel: () -> Void
    let onComplete: () -> Void

    var body: some View {
        Form {
            Section {
                Text(title).font(.headline)
                Text("Controlled data only. This screen does not sign in or change Home Assistant or ChargePoint settings.")
                    .fixedSize(horizontal: false, vertical: true)
            }
            Section {
                Button("Complete controlled return", action: onComplete)
                    .frame(minHeight: 44)
            }
        }
        .navigationTitle("Controlled setup")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel", action: onCancel).frame(minHeight: 44)
            }
        }
    }
}
