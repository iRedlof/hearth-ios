import SwiftUI
import WidgetKit
import HearthKit

/// Auth state tracking for sign-in toast detection
private enum AuthState: Equatable {
    case signedOut
    case signedIn
    case expired
}

/// The iOS Home dashboard: assembles all Phase-2 components (header, widgets strip, connections, every day, look, footer).
/// Fetches live snapshots (car, alarm, CP, thermostat) and maps them to WidgetHealth + stateLine for the widgets strip.
struct HomeView: View {
    let config: HaConfig
    var onRoute: (HomeRoute) -> Void
    var onRefresh: (() -> Void)?
    var onSignOut: (() -> Void)?

    @State private var car: CarSnapshot?
    @State private var alarm: AlarmSnapshot?
    @StateObject private var thermostat = ThermostatLiveModel()
    @State private var cp: CpSnapshot?
    @State private var cpSignedIn = (try? CpSessionStore.context().session.isSignedIn) == true
    @State private var loading = true
    @State private var loadID = UUID()
    @State private var toastMessage: String?
    @State private var previousAuthState: AuthState?
    @State private var previousWidgetHealth: [HomeWidgetKind: WidgetHealth] = [:]
    @ObservedObject private var refreshSignal = RefreshSignal.shared

    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack(alignment: .bottom) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    HomeHeader(onRefresh: onRefresh, onSignOut: onSignOut)

                // First-run Get-started OR Sign-in banner
                let ha = haConnectionStatus(config)
                let kinds = configuredWidgets(config: config, chargePointSignedIn: cpSignedIn)
                // Single source of truth: the stored session drives the Connections row and the tile.
                let cpStatus = currentCpStatus()

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
                    cp: cpStatus,
                    onTap: onRoute
                )

                // Every day section
                EveryDaySection(onTap: onRoute)

                // Look section
                LookSection(summary: CardStyleStore.global().summary, onTap: onRoute)

                    HomeFooter()
                }
            }
            .background(HearthColor.page(scheme).ignoresSafeArea())

            if let message = toastMessage {
                ToastOverlay(message: message) {
                    toastMessage = nil
                }
                .transition(reduceMotion ? .identity : .move(edge: .bottom).combined(with: .opacity))
                .hearthContentAnimation(value: toastMessage, reduceMotion: reduceMotion)
            }
        }
        .task(id: config) { await load() }
        .onDisappear { thermostat.close() }
        .onChange(of: refreshSignal.tick) { Task { await load() } }
        .onChange(of: refreshSignal.thermostatRefresh) {
            if let request = refreshSignal.thermostatRefresh {
                thermostat.refresh(request, source: .dashboardRefresh)
                RefreshSignal.shared.thermostatRefresh = nil
            }
        }
        .onChange(of: config) { _, newConfig in
            detectSignInTransition(newConfig: newConfig)
        }
    }

    // MARK: - Helpers

    /// The one ChargePoint status all Home surfaces read, from the current stored session.
    private func currentCpStatus() -> CpConnectionStatus {
        guard let session = try? CpSessionStore.context().session else { return .notSetUp }
        return cpConnectionStatus(for: session)
    }

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
            // CP snapshot uses `stale` for error state, no separate error field. The tile agrees with
            // the Connections row and the widget by deriving needs-sign-in from the same status.
            let needsSignIn = currentCpStatus() == .needsSignIn
            let health = widgetHealth(stale: cp.stale, error: false, needsSettings: false, needsSignIn: needsSignIn)
            let stateLine = cpTileStateLine(bigAnswer: cp.bigAnswer, unit: cp.unit, stale: cp.stale)
            readings[.chargePoint] = WidgetReading(health: health, stateLine: stateLine)
        }

        return homeWidgetItems(kinds: kinds, readings: readings)
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
        guard !names.isEmpty else { return "" }
        guard names.count > 1 else { return names[0] }
        return names.dropLast().joined(separator: ", ") + " and " + names.last!
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
        if loadID == requestID {
            loading = false
            // A background refresh may have set `expired`; keep the signed-in flag honest so the
            // Connections row and the widget configuration match what the widget now shows.
            cpSignedIn = (try? CpSessionStore.context().session.isSignedIn) == true
            // Snapshot widget health when signed out/expired for future comparison
            let currentState = authState(from: config)
            if currentState == .signedOut || currentState == .expired {
                previousWidgetHealth = currentWidgetHealth()
            }
        }
    }

    private func detectSignInTransition(newConfig: HaConfig) {
        let newAuthState = authState(from: newConfig)
        defer { previousAuthState = newAuthState }

        // Only fire toast on signed-out/expired → signed-in transition
        guard let previous = previousAuthState,
              (previous == .signedOut || previous == .expired),
              newAuthState == .signedIn else { return }

        // Snapshot current widget health after sign-in
        let currentHealth = currentWidgetHealth()
        let recoveredCount = countRecoveredWidgets(previousHealth: previousWidgetHealth, currentHealth: currentHealth)

        if let message = signedInToastMessage(recoveredCount: recoveredCount) {
            toastMessage = message
            Task {
                try? await Task.sleep(for: .seconds(4))
                if toastMessage == message { toastMessage = nil }
            }
        }
    }

    private func authState(from config: HaConfig) -> AuthState {
        if config.isSignedIn {
            return .signedIn
        } else if config.hasAuth {
            return .expired
        } else {
            return .signedOut
        }
    }

    private func currentWidgetHealth() -> [HomeWidgetKind: WidgetHealth] {
        let items = builtItems()
        var health: [HomeWidgetKind: WidgetHealth] = [:]
        for item in items {
            health[item.kind] = item.health
        }
        return health
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
        onRoute: { _ in }
    )
    .preferredColorScheme(.light)
}

#Preview("Populated — Dark") {
    HomeView(
        config: .populated,
        onRoute: { _ in }
    )
    .preferredColorScheme(.dark)
}

#Preview("First-run — Light") {
    HomeView(
        config: HaConfig(baseUrl: "", token: "", entityId: ""),
        onRoute: { _ in }
    )
    .preferredColorScheme(.light)
}

#Preview("First-run — Dark") {
    HomeView(
        config: HaConfig(baseUrl: "", token: "", entityId: ""),
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
        onRoute: { _ in }
    )
    .preferredColorScheme(.dark)
}

#Preview("Large text — Light") {
    HomeView(
        config: .populated,
        onRoute: { _ in }
    )
    .environment(\.sizeCategory, .accessibilityExtraLarge)
    .preferredColorScheme(.light)
}
