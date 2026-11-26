import SwiftUI
import WidgetKit
import HearthKit

@main
struct HearthApp: App {
    #if DEBUG
    private let probeSelection: CarRouteProbeSelection
    #endif
    init() {
        HearthFontRegistration.registerIfNeeded()
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
                else if Self.designGallery() { DesignSystemGallery() }
                else if let preview = Self.homePreview() { HomePreviewFixture(previewCase: preview) }
                else if let page = Self.phase3Page() { Phase3PageFixture(pageCase: page) }
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

    private static func designGallery() -> Bool {
        return ProcessInfo.processInfo.arguments.contains("-designGallery")
    }

    private static func homePreview() -> HomePreviewCase? {
        let args = ProcessInfo.processInfo.arguments
        if args.contains("-homePreviewFirstRun") { return .firstRun }
        if args.contains("-homePreview") { return .populated }
        return nil
    }

    private static func phase3Page() -> Phase3PageCase? {
        let args = ProcessInfo.processInfo.arguments
        if args.contains("-haPage") { return .haConnected }
        if args.contains("-haPageNeedsSignIn") { return .haNeedsSignIn }
        if args.contains("-cpPage") { return .cpConnected }
        if args.contains("-cpPageNotSetUp") { return .cpNotSetUp }
        if args.contains("-cpAlerts") { return .cpAlerts }
        return nil
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
    @Environment(\.scenePhase) private var scenePhase
    @State private var config: HaConfig?
    @State private var selection = ContentView.initialTab()
    @ObservedObject private var climateGate = ClimateGate.shared
    @ObservedObject private var garageGate = GarageGate.shared
    @ObservedObject private var cpSetup = CpSetupGate.shared
    @ObservedObject private var haSetup = HaSetupGate.shared
    @ObservedObject private var carReadings = CarReadingsGate.shared
    @State private var presentedSheet: HearthSheet?
    @State private var settingsCarReturn: CarReadingsRequest?
    @State private var thermostatAdmission = ThermostatRouteAdmission()
    @State private var thermostatModel: ThermostatControlsModel?
    @State private var settingsThermostatReturn: ThermostatRecoveryReturn?
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
            retireThermostat()
            presentedSheet = .chargePointPage(route, UUID())
        }
        .onChange(of: carReadings.request, initial: true) {
            guard let request = carReadings.request else { return }
            carReadings.request = nil
            presentCarReadings(request)
        }
        .onOpenURL { url in
            if let destination = alarmReadingsDestination(from: url) {
                guard destination != .inert else { return }
                settingsCarReturn = nil
                retireThermostat()
                presentedSheet = .alarm(destination, UUID())
                return
            }
            if let destination = thermostatDestination(from: url) {
                presentThermostat(destination)
                return
            }
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
            retireThermostat()
            if !inertTabs { config = HaConfigStore.load() }
            presentedSheet = .homeAssistantPage(UUID())
        }
        .onChange(of: presentedSheet?.id) {
            if let sheet = presentedSheet, case .thermostat = sheet { return }
            thermostatModel?.close(); thermostatModel = nil; thermostatAdmission.close()
        }
        .onChange(of: scenePhase) { _, newPhase in
            if !inertTabs && newPhase == .active {
                HouseScheduler.refreshScheduleIfNeeded()
            }
        }
        #if DEBUG
        .onAppear { handleDebugLaunchArgs() }
        #endif
        .onAppear {
            if !inertTabs {
                HouseScheduler.refreshScheduleIfNeeded()
            }
        }
        .sheet(item: $presentedSheet) { sheet in
            switch sheet {
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
            case .thermostat(let request):
                if let model = thermostatModel, model.request.eventID == request.eventID {
                    ThermostatControlsScreen(model: model,
                        onClose: {
                            guard presentedSheet?.id == sheet.id else { return }
                            retireThermostat(); presentedSheet = nil
                        }, onSettings: {
                            guard presentedSheet?.id == sheet.id else { return }
                            let returning = ThermostatRecoveryReturn(original: request)
                            thermostatModel?.close(); thermostatAdmission.close()
                            settingsCarReturn = nil; settingsThermostatReturn = returning
                            selection = 1; presentedSheet = nil
                        }, onReconnect: {
                            guard presentedSheet?.id == sheet.id else { return }
                            let returning = ThermostatRecoveryReturn(original: request)
                            thermostatModel?.close(); thermostatAdmission.close(); settingsCarReturn = nil
                            settingsThermostatReturn = nil
                            presentedSheet = .thermostatReconnect(returning)
                        })
                        .id(request.eventID)
                }
            case .thermostatReconnect(let returning):
                NavigationStack {
                    if inertTabs {
                        ControlledSetupScreen(title: "Controlled Home Assistant reconnect",
                            onCancel: { finishThermostatReconnect(sheet, completed: false) },
                            onComplete: { finishThermostatReconnect(sheet, completed: true) })
                    } else {
                        SignInView(initialURL: config?.baseUrl) { finishThermostatReconnect(sheet, completed: true) }
                            .toolbar { ToolbarItem(placement: .cancellationAction) {
                                Button("Cancel") { finishThermostatReconnect(sheet, completed: false) }.frame(minHeight: 44)
                            } }
                    }
                }.id(returning.transitionID).interactiveDismissDisabled()
            case .alarm(let destination, _):
                AlarmReadingsScreen(destination: destination, inert: inertTabs,
                    onSettings: { presentedSheet = nil; selection = 1 },
                    onReconnect: { presentedSheet = .reconnect(UUID(), returningTo: nil) })
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
            case .homeAssistantPage(_):
                NavigationStack {
                    HomeAssistantPage(config: config, runtime: LiveSettingsRuntime.shared) {
                        config = $0
                    }
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Done") {
                                guard presentedSheet?.id == sheet.id else { return }
                                if !inertTabs { config = HaConfigStore.load() }
                                presentedSheet = nil
                            }
                        }
                    }
                }
                .id(sheet.id)
            case .chargePointPage(let initialRoute, _):
                NavigationStack {
                    ChargePointPage(initialRoute: initialRoute, runtime: LiveSettingsRuntime.shared)
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Done") {
                                    guard presentedSheet?.id == sheet.id else { return }
                                    presentedSheet = nil
                                }
                            }
                        }
                }
                .id(sheet.id)
            case .widgetPage(let kind, _):
                NavigationStack {
                    WidgetPage(kind: kind, config: config, onRoute: handleHomeRoute) { next in
                        config = next
                    }
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Done") {
                                guard presentedSheet?.id == sheet.id else { return }
                                if !inertTabs { config = HaConfigStore.load() }
                                presentedSheet = nil
                            }
                        }
                    }
                }
                .id(sheet.id)
            case .addWidgetGallery(_):
                NavigationStack {
                    AddWidgetGallery(
                        config: config,
                        cpSignedIn: (try? CpSessionStore.context().session.isSignedIn) == true,
                        onPick: { kind in
                            presentedSheet = .widgetPage(kind, UUID())
                        },
                        onConnectHA: {
                            presentedSheet = .homeAssistantPage(UUID())
                        }
                    )
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Done") {
                                guard presentedSheet?.id == sheet.id else { return }
                                presentedSheet = nil
                            }
                        }
                    }
                }
                .id(sheet.id)
            case .cardStylePage(let kind, _):
                NavigationStack {
                    CardStylePage(kind: kind)
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Done") {
                                    guard presentedSheet?.id == sheet.id else { return }
                                    presentedSheet = nil
                                }
                            }
                        }
                }
                .id(sheet.id)
            case .morningCommute(_):
                NavigationStack {
                    MorningCommutePage()
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Done") {
                                    guard presentedSheet?.id == sheet.id else { return }
                                    presentedSheet = nil
                                }
                            }
                        }
                }
                .id(sheet.id)
            }
        }
    }

    /// URL delivery remains local to this scene; compatible intent delivery shares this sink.
    private func presentCarReadings(_ request: CarReadingsRequest) {
        guard request.destination != .inert else { return }
        settingsCarReturn = nil
        retireThermostat()
        presentedSheet = .car(request)
    }

    private func retireThermostat() {
        thermostatModel?.close(); thermostatModel = nil; thermostatAdmission.close()
        settingsThermostatReturn = nil
        if !inertTabs { ClimateGate.shared.retire() }
    }
    private func presentThermostat(_ destination: ThermostatDestination) {
        guard let request = thermostatAdmission.admit(destination) else { return }
        settingsCarReturn = nil; settingsThermostatReturn = nil
        if thermostatModel?.request.eventID == request.eventID {
            thermostatModel?.revalidate()
            return
        }
        thermostatModel?.close()
        if !inertTabs { ClimateGate.shared.retire() }
        thermostatModel = ThermostatControlsModel(request: request,
            runtime: inertTabs ? ThermostatReadingsRuntime(tickets: nil, state: nil) : .live)
        presentedSheet = .thermostat(request)
    }
    private func finishThermostatReconnect(_ sheet: HearthSheet, completed: Bool) {
        guard presentedSheet?.id == sheet.id,
              case .thermostatReconnect(let returning) = sheet else { return }
        if completed, !inertTabs { config = HaConfigStore.load() }
        thermostatAdmission.close()
        presentThermostat(returning.original.destination)
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
            HomeView(config: config, onSignOut: signOut, onRoute: handleHomeRoute)
        } else {
            SignInView(onSignedIn: { config = HaConfigStore.load() })
        }
    }

    private func handleHomeRoute(_ route: HomeRoute) {
        switch route {
        case .homeAssistant:
            // Present Home Assistant page
            settingsCarReturn = nil
            retireThermostat()
            presentedSheet = .homeAssistantPage(UUID())
        case .chargePoint:
            // Present ChargePoint page
            settingsCarReturn = nil
            retireThermostat()
            presentedSheet = .chargePointPage(nil, UUID())
        case .widget(let kind):
            // Present per-widget config page
            settingsCarReturn = nil
            retireThermostat()
            presentedSheet = .widgetPage(kind, UUID())
        case .addWidget:
            // Present widget gallery
            settingsCarReturn = nil
            retireThermostat()
            presentedSheet = .addWidgetGallery(UUID())
        case .cardStyle(let kind):
            // Present the card-style page (global when kind is nil, per-widget override otherwise)
            settingsCarReturn = nil
            retireThermostat()
            presentedSheet = .cardStylePage(kind, UUID())
        case .settings:
            // Go to Settings tab
            selection = 1
        }
    }

    @ViewBuilder private var settingsTab: some View {
        Group {
            if inertTabs { Text("Controlled Car route fixture · Settings tab") }
            else {
                SettingsView(config: config, onChange: { config = $0 }, onOpenGallery: {
                    presentedSheet = .addWidgetGallery(UUID())
                })
                .id(HaConfigStore.requestScope())
            }
        }
        .safeAreaInset(edge: .top) {
            if let returning = settingsThermostatReturn {
                Button {
                    guard settingsThermostatReturn?.transitionID == returning.transitionID,
                          presentedSheet?.id == nil, thermostatAdmission.active == nil else { return }
                    presentThermostat(returning.original.destination)
                } label: {
                    Label("Back to thermostat readings", systemImage: "thermometer.medium")
                        .font(.body.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                }.padding(.horizontal).background(.regularMaterial)
            } else if let original = settingsCarReturn {
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
        if inertTabs {
            Text("Controlled Car route fixture · Preview tab")
        } else {
            NavigationStack {
                AddWidgetGallery(
                    config: config,
                    cpSignedIn: (try? CpSessionStore.context().session.isSignedIn) == true,
                    onPick: { kind in
                        presentedSheet = .widgetPage(kind, UUID())
                    },
                    onConnectHA: {
                        presentedSheet = .homeAssistantPage(UUID())
                    }
                )
            }
        }
    }

    private func signOut() {
        do {
            try HaConfigStore.clear()
            Task { await HaAuth.shared.forget() }
            WidgetCenter.shared.reloadAllTimelines()
            config = nil
        } catch { signOutError = friendlyError(error) }
    }

    #if DEBUG
    /// Phase 4 widget DEBUG launch hooks (applied after initial tab/fixture setup)
    private func handleDebugLaunchArgs() {
        guard !inertTabs, presentedSheet == nil else { return }
        let args = ProcessInfo.processInfo.arguments
        if args.contains("-addGallery") {
            presentedSheet = .addWidgetGallery(UUID())
        } else if let index = args.firstIndex(of: "-widgetPage"), index + 1 < args.count,
                  let kind = HomeWidgetKind(rawValue: args[index + 1]) {
            presentedSheet = .widgetPage(kind, UUID())
        } else if args.contains("-cardStyle") {
            presentedSheet = .cardStylePage(nil, UUID())
        } else if args.contains("-glancePreview") {
            presentedSheet = .widgetPage(.glance, UUID())
        } else if args.contains("-morningCommute") {
            presentedSheet = .morningCommute(UUID())
        }
    }
    #endif
}

private struct ThermostatRecoveryReturn {
    let original: ThermostatRouteRequest
    let transitionID = UUID()
}
private enum HearthSheet: Identifiable {
    case reconnect(UUID, returningTo: CarReadingsRequest?)
    case car(CarReadingsRequest)
    case alarm(AlarmReadingsDestination, UUID)
    case thermostat(ThermostatRouteRequest)
    case thermostatReconnect(ThermostatRecoveryReturn)
    case homeAssistantPage(UUID)
    case chargePointPage(CpSetupRoute?, UUID)
    case widgetPage(HomeWidgetKind, UUID)
    case addWidgetGallery(UUID)
    case cardStylePage(HomeWidgetKind?, UUID)
    case morningCommute(UUID)
    var id: String {
        switch self {
        case .reconnect(let id, _): "reconnect:\(id)"
        case .car(let request): "car:\(request.id)"
        case .alarm(_, let id): "alarm:\(id)"
        case .thermostat(let request): "thermostat:\(request.eventID)"
        case .thermostatReconnect(let returning): "thermostatReconnect:\(returning.transitionID)"
        case .homeAssistantPage(let id): "homeAssistantPage:\(id)"
        case .chargePointPage(_, let id): "chargePointPage:\(id)"
        case .widgetPage(let kind, let id): "widgetPage:\(kind.rawValue):\(id)"
        case .addWidgetGallery(let id): "addWidgetGallery:\(id)"
        case .cardStylePage(let kind, let id): "cardStylePage:\(kind?.rawValue ?? "global"):\(id)"
        case .morningCommute(let id): "morningCommute:\(id)"
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

#if DEBUG
private enum HomePreviewCase {
    case populated, firstRun
}

private enum Phase3PageCase {
    case haConnected, haNeedsSignIn, cpConnected, cpNotSetUp, cpAlerts
}

/// DEBUG-only fixture for rendering HomeView states without signing in.
private struct HomePreviewFixture: View {
    let previewCase: HomePreviewCase

    var body: some View {
        HomeView(
            config: fixtureConfig,
            onSignOut: {},
            onRoute: { _ in }
        )
    }

    private var fixtureConfig: HaConfig {
        switch previewCase {
        case .populated:
            return HaConfig(
                baseUrl: "https://home.example.com",
                token: "mock-token",
                entityId: "alarm_control_panel.home",
                refreshToken: "mock-refresh-token",
                lockId: "lock.front_door",
                climateId: "climate.thermostat",
                sensorsJson: "[\"sensor.temp\"]"
            )
        case .firstRun:
            return HaConfig(baseUrl: "", token: "", entityId: "")
        }
    }
}

/// DEBUG-only fixture for rendering Phase 3 settings pages with mock data.
private struct Phase3PageFixture: View {
    let pageCase: Phase3PageCase

    var body: some View {
        NavigationStack {
            switch pageCase {
            case .haConnected:
                HomeAssistantPage(config: mockHaConfig, runtime: MockPhase3Runtime()) { _ in }
            case .haNeedsSignIn:
                HomeAssistantPage(config: nil, runtime: MockPhase3Runtime()) { _ in }
            case .cpConnected:
                ChargePointPage(initialRoute: nil, runtime: MockPhase3Runtime())
            case .cpNotSetUp:
                ChargePointPage(initialRoute: nil, runtime: MockPhase3RuntimeNotSetUp())
            case .cpAlerts:
                ChargePointAlertsPage(runtime: MockPhase3Runtime())
            }
        }
    }

    private var mockHaConfig: HaConfig {
        HaConfig(
            baseUrl: "https://home.example.com",
            token: "mock-token",
            entityId: "alarm_control_panel.home",
            refreshToken: "mock-refresh-token",
            lockId: "lock.front_door",
            climateId: "climate.thermostat",
            sensorsJson: "[\"sensor.temp\"]"
        )
    }
}

@MainActor
private final class MockPhase3Runtime: SettingsRuntime {
    func loadHa() -> HaStoreSnapshot? {
        HaStoreSnapshot(
            config: HaConfig(
                baseUrl: "https://home.example.com",
                token: "mock-token",
                entityId: "alarm_control_panel.home",
                refreshToken: "mock-refresh-token",
                lockId: "lock.front_door",
                climateId: "climate.thermostat",
                sensorsJson: "[\"sensor.temp\"]"
            ),
            scope: "mock-scope"
        )
    }

    func saveHaEdit(expectedScope: String?, edit: SettingsHaEdit) throws -> HaConfig? {
        nil
    }

    func discoverHa(config: HaConfig, scope: String?, purpose: SettingsDiscoveryPurpose) async throws -> SettingsDiscovery {
        throw HaError("Mock discovery")
    }

    func loadCp() -> SettingsCpState {
        SettingsCpState(
            session: CpSession(token: "mock-token", userId: 1, email: "user@example.com"),
            location: CpLocation(
                name: "Office Building",
                address: "123 Main St",
                deviceIds: [1, 2],
                bounds: cpBounds(lat: 37.7749, lon: -122.4194),
                label: "Office"
            ),
            auto: true,
            alerts: CpAlertPrefs(offer: true, accepted: true, snoozed: false, second: true)
        )
    }

    func performCpEdit(_ edit: SettingsCpEdit, expected: CpSettingsOrigin?) async throws -> SettingsCpState {
        loadCp()
    }

    func openSetupRoute(_ route: SettingsSetupRoute) -> SettingsSetupDestination {
        .fixture
    }

    func refreshWidgets(kinds: Set<String>) {}
}

@MainActor
private final class MockPhase3RuntimeNotSetUp: SettingsRuntime {
    func loadHa() -> HaStoreSnapshot? { nil }

    func saveHaEdit(expectedScope: String?, edit: SettingsHaEdit) throws -> HaConfig? {
        nil
    }

    func discoverHa(config: HaConfig, scope: String?, purpose: SettingsDiscoveryPurpose) async throws -> SettingsDiscovery {
        throw HaError("Mock discovery")
    }

    func loadCp() -> SettingsCpState {
        SettingsCpState(
            session: CpSession(token: "", userId: 0, email: ""),
            location: nil,
            auto: false,
            alerts: CpAlertPrefs()
        )
    }

    func performCpEdit(_ edit: SettingsCpEdit, expected: CpSettingsOrigin?) async throws -> SettingsCpState {
        loadCp()
    }

    func openSetupRoute(_ route: SettingsSetupRoute) -> SettingsSetupDestination {
        .fixture
    }

    func refreshWidgets(kinds: Set<String>) {}
}
#endif
