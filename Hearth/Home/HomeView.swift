import SwiftUI
import WidgetKit
import HearthKit

/// The iOS Home dashboard: assembles all Phase-2 components (header, widgets strip, connections, every day, look, footer).
/// Fetches live snapshots (car, alarm, CP, thermostat) and maps them to WidgetHealth + stateLine for the widgets strip.
struct HomeView: View {
    let config: HaConfig
    var onSignOut: () -> Void
    var onRoute: (HomeRoute) -> Void

    @State private var car: CarSnapshot?
    @State private var alarm: AlarmSnapshot?
    @StateObject private var thermostat = ThermostatLiveModel()
    @State private var cp: CpSnapshot?
    @State private var cpSignedIn = (try? CpSessionStore.context().session.isSignedIn) == true
    @State private var loading = true
    @State private var loadID = UUID()
    @State private var toastMessage: String?
    @ObservedObject private var refreshSignal = RefreshSignal.shared

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ZStack(alignment: .bottom) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    HomeHeader()

                // First-run Get-started OR Sign-in banner
                let ha = haConnectionStatus(config)
                let kinds = configuredWidgets(config: config, chargePointSignedIn: cpSignedIn)
                let cpSession = try? CpSessionStore.context().session
                let cpHasAccount = (cpSession?.userId ?? 0) != 0 || !(cpSession?.email ?? "").isEmpty

                if ha == .needsSignIn {
                    signInBanner()
                } else if showGetStarted(haConnected: ha == .connected, widgetCount: kinds.count) {
                    GetStartedCard(
                        haConnected: ha == .connected,
                        hasWidget: !kinds.isEmpty,
                        onConnect: { onRoute(.homeAssistant) },
                        onAddWidget: { onRoute(.addWidget) }
                    )
                }

                // Your widgets header + strip
                YourWidgetsHeader(onAdd: { onRoute(.addWidget) })
                YourWidgetsStrip(items: builtItems(), onTap: onRoute)

                // Connections section
                ConnectionsSection(
                    ha: ha,
                    cp: cpConnectionStatus(signedIn: cpSignedIn, hasAccount: cpHasAccount),
                    onTap: onRoute
                )

                // Every day section
                EveryDaySection(onTap: onRoute)

                // Look section
                LookSection(onTap: onRoute)

                    HomeFooter()
                }
            }
            .background(HearthColor.page(scheme).ignoresSafeArea())

            if let message = toastMessage {
                ToastOverlay(message: message) {
                    toastMessage = nil
                }
            }
        }
        .task(id: config) { await load() }
        .onDisappear { thermostat.close() }
        .onChange(of: refreshSignal.tick) { Task { await load() } }
        .onChange(of: refreshSignal.thermostatRefresh) {
            if let request = refreshSignal.thermostatRefresh { thermostat.refresh(request, source: .glyphRefresh) }
        }
    }

    // MARK: - Helpers

    private func builtItems() -> [HomeWidgetItem] {
        let kinds = configuredWidgets(config: config, chargePointSignedIn: cpSignedIn)
        var readings: [HomeWidgetKind: WidgetReading] = [:]

        if let car {
            let health = widgetHealth(stale: car.stale, error: car.error != nil, needsSettings: car.needsSettings, needsSignIn: car.needsSignIn)
            let stateLine = car.stale ? "Stale data" : car.chargeLine
            readings[.car] = WidgetReading(health: health, stateLine: stateLine)
        }

        if let alarm {
            let health = widgetHealth(stale: alarm.stale, error: alarm.error != nil, needsSettings: alarm.needsSettings, needsSignIn: alarm.needsSignIn)
            let stateLine = alarm.stale ? "Stale data" : alarm.stateWord
            readings[.alarm] = WidgetReading(health: health, stateLine: stateLine)
        }

        if let entry = thermostat.entry {
            let presentation = entry.presentation
            let thermostatError = presentation.recovery != .none
            let health = widgetHealth(stale: false, error: thermostatError, needsSettings: presentation.configuration != .ready, needsSignIn: presentation.configuration == .needsAuthentication)
            let stateLine: String
            if let temp = presentation.room.value, case .number(let val) = temp {
                stateLine = "\(Int(val.rounded()))°"
            } else if let state = presentation.state, let action = state.action {
                stateLine = action.capitalized
            } else if let state = presentation.state {
                stateLine = state.mode.capitalized
            } else {
                stateLine = "Unavailable"
            }
            readings[.thermostat] = WidgetReading(health: health, stateLine: stateLine)
        }

        if let cp {
            // CP snapshot uses `stale` for error state, no separate error field
            let health = widgetHealth(stale: cp.stale, error: false, needsSettings: false, needsSignIn: false)
            let stateLine = cp.stale ? "Stale data" : cp.bigAnswer
            readings[.chargePoint] = WidgetReading(health: health, stateLine: stateLine)
        }

        return homeWidgetItems(kinds: kinds, readings: readings)
    }

    private func needsSignInBanner() -> Bool {
        let haStatus = haConnectionStatus(config)
        let cpSession = try? CpSessionStore.context().session
        let cpHasAccount = (cpSession?.userId ?? 0) != 0 || !(cpSession?.email ?? "").isEmpty
        let cpStatus = cpConnectionStatus(signedIn: cpSignedIn, hasAccount: cpHasAccount)
        return haStatus == .needsSignIn || cpStatus == .needsSignIn
    }

    @ViewBuilder
    private func signInBanner() -> some View {
        let haStatus = haConnectionStatus(config)
        if haStatus == .needsSignIn {
            let affectedWidgets = affectedWidgetNames()
            let detail = affectedWidgets.isEmpty ? nil : "\(affectedWidgets) are paused"
            SignInBanner(
                title: "Home Assistant needs sign-in",
                detail: detail
            ) {
                onRoute(.homeAssistant)
            }
        }
        // CP banner would go here if needed
    }

    private func affectedWidgetNames() -> String {
        let kinds = configuredWidgets(config: config, chargePointSignedIn: cpSignedIn)
        let names = kinds.compactMap { kind -> String? in
            switch kind {
            case .thermostat: return "Hallway thermostat"
            case .alarm: return "Home alarm"
            case .lights: return "Lights"
            case .car: return "Stargate"
            case .chargePoint: return nil
            case .glance, .doors, .quick, .favourites, .activity, .battery:
                return kind.displayName
            }
        }
        return names.isEmpty ? "" : names.joined(separator: ", ")
    }


    private func load() async {
        thermostat.loadCache()
        let requestID = UUID()
        loadID = requestID
        loading = true
        let now = Date(), selected = config
        await withTaskGroup(of: CardResult.self) { group in
            group.addTask { .car(await CarLiveSnapshot.fetch(now: now)) }
            group.addTask { .alarm(selected.isComplete ? await AlarmLiveSnapshot.fetch(now: now) : nil) }
            group.addTask { .chargePoint(await CpLiveSnapshot.fetch(now: now)) }
            for await result in group {
                guard !Task.isCancelled, loadID == requestID else { group.cancelAll(); return }
                switch result {
                case .car(let snapshot): car = snapshot
                case .alarm(let snapshot): alarm = snapshot.map { AlarmLiveSnapshot.currentFeedback($0) }
                case .chargePoint(let snapshot): cp = snapshot
                }
            }
        }
        if loadID == requestID { loading = false }
    }

    private enum CardResult: Sendable {
        case car(CarSnapshot), alarm(AlarmSnapshot?), chargePoint(CpSnapshot)
    }
}

// MARK: - Previews

private extension HaConfig {
    static var populated: HaConfig {
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

#Preview("Populated — Light") {
    HomeView(
        config: .populated,
        onSignOut: {},
        onRoute: { _ in }
    )
    .preferredColorScheme(.light)
}

#Preview("Populated — Dark") {
    HomeView(
        config: .populated,
        onSignOut: {},
        onRoute: { _ in }
    )
    .preferredColorScheme(.dark)
}

#Preview("First-run — Light") {
    HomeView(
        config: HaConfig(baseUrl: "", token: "", entityId: ""),
        onSignOut: {},
        onRoute: { _ in }
    )
    .preferredColorScheme(.light)
}

#Preview("First-run — Dark") {
    HomeView(
        config: HaConfig(baseUrl: "", token: "", entityId: ""),
        onSignOut: {},
        onRoute: { _ in }
    )
    .preferredColorScheme(.dark)
}

#Preview("Needs sign-in — Light") {
    HomeView(
        config: HaConfig(
            baseUrl: "https://home.example.com",
            token: "",
            entityId: "alarm_control_panel.home"
        ),
        onSignOut: {},
        onRoute: { _ in }
    )
    .preferredColorScheme(.light)
}

#Preview("Needs sign-in — Dark") {
    HomeView(
        config: HaConfig(
            baseUrl: "https://home.example.com",
            token: "",
            entityId: "alarm_control_panel.home"
        ),
        onSignOut: {},
        onRoute: { _ in }
    )
    .preferredColorScheme(.dark)
}

#Preview("Large text — Light") {
    HomeView(
        config: .populated,
        onSignOut: {},
        onRoute: { _ in }
    )
    .environment(\.sizeCategory, .accessibilityExtraLarge)
    .preferredColorScheme(.light)
}
