import SwiftUI
import WidgetKit
import HearthKit

/// The "Live" tab: the real Car and — once an alarm panel is configured — the real Alarm, each
/// rendered through the SAME Beacon view the home-screen widget uses. The Alarm card's arm/disarm
/// and door buttons are the live interactive buttons (AppIntents), so this is both the dashboard
/// and the on-device verification surface.
struct LiveDashboardView: View {
    let config: HaConfig
    var onSignOut: () -> Void

    @State private var car: CarSnapshot?
    @State private var alarm: AlarmSnapshot?
    @StateObject private var thermostat = ThermostatLiveModel()
    @State private var cpDisplays: [CpTimelineDisplay] = []
    @State private var cpSignedIn = false
    @State private var cpLoading = true
    @State private var cpLoadID = UUID()
    @State private var visible = false
    @State private var activeConfig: HaConfig?
    @State private var displayClock = Date()
    @Environment(\.scenePhase) private var scenePhase
    @State private var showCpSignIn = false
    @State private var loading = true
    @State private var loadID = UUID()
    @ObservedObject private var refreshSignal = RefreshSignal.shared

    var body: some View {
        let loadConfig = visible ? config : nil
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header
                sectionTitle("Car")
                card { if let car { CarBeaconView(car) } else { placeholder } }
                if config.isComplete {
                    sectionTitle("Alarm")
                    card { if let alarm { AlarmBeaconView(alarm) } else { placeholder } }
                }
                if config.hasClimate {
                    sectionTitle("Thermostat")
                    card(dimmed: thermostat.checking) {
                        if let entry = thermostat.entry { ThermostatBeaconView(entry) } else { placeholder }
                    }
                    if let entry = thermostat.entry {
                        if let observed = thermostatSavedObservation(entry.presentation) {
                            Text("Saved reading · \(thermostatObservationText(observed))")
                                .font(.callout).foregroundStyle(.secondary)
                                .accessibilityLabel("Saved reading, \(thermostatObservationText(observed))")
                        } else { Text("No saved reading").font(.callout).foregroundStyle(.secondary) }
                        if let url = thermostatReadingsURL(for: entry.destination) {
                            Link("Open readings and controls", destination: url).frame(minHeight: 44)
                        }
                    }
                    Text("Refresh checks Home Assistant. Automatic loading uses saved thermostat readings.")
                        .font(.callout).foregroundStyle(.secondary)
                }
                sectionTitle("ChargePoint")
                card(dimmed: cpLoading) { chargePointCard }
                if !cpSignedIn {
                    Button { showCpSignIn = true } label: {
                        Label("Connect ChargePoint", systemImage: "bolt.fill").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent).tint(.orange)
                }
                controls
            }
            .padding(20)
        }
        .background(Color(white: 0.08).ignoresSafeArea())
        .preferredColorScheme(.dark)
        .onAppear { visible = true }
        .task(id: loadConfig) {
            guard visible, let loadConfig, !Task.isCancelled else { return }
            activeConfig = loadConfig
            await load()
        }
        .onDisappear {
            visible = false
            retireLoads()
            thermostat.close()
        }
        .onChange(of: refreshSignal.tick) { Task { await load() } }
        .onChange(of: refreshSignal.cpSourceTick) { Task { await loadChargePoint() } }
        .onChange(of: scenePhase) {
            if scenePhase == .active { displayClock = Date() }
        }
        .onChange(of: refreshSignal.thermostatRefresh) {
            if let request = refreshSignal.thermostatRefresh { thermostat.refresh(request, source: .glyphRefresh) }
        }
        .sheet(isPresented: $showCpSignIn) {
            NavigationStack {
                CpSignInView(onSignedIn: {
                    showCpSignIn = false
                })
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Live").font(.title3.weight(.bold))
            Text(config.baseUrl)
                .font(.caption2).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
        }
    }

    private func sectionTitle(_ t: String) -> some View {
        Text(t).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func card<V: View>(dimmed: Bool? = nil, @ViewBuilder _ content: () -> V) -> some View {
        content()
            .frame(height: 174).frame(maxWidth: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .shadow(color: .black.opacity(0.25), radius: 6, y: 3)
            .opacity((dimmed ?? loading) ? 0.5 : 1)   // dim while a refresh is in flight
    }

    private var placeholder: some View {
        ZStack { Color(white: 0.12); ProgressView() }
    }

    @ViewBuilder private var chargePointCard: some View {
        if visible, activeConfig == config, !cpDisplays.isEmpty {
            if cpDisplays.contains(where: { $0.date > max(displayClock, Date()) }) {
                TimelineView(.explicit(cpDisplays.map(\.date))) { context in
                    if let snapshot = cpTimelineSnapshot(cpDisplays, at: max(context.date, displayClock)) {
                        CpBeaconView(snapshot)
                    } else { placeholder }
                }
                .id(cpLoadID)
            } else if let snapshot = cpTimelineSnapshot(cpDisplays, at: max(displayClock, Date())) {
                CpBeaconView(snapshot)
            } else { placeholder }
        } else { placeholder }
    }

    private var controls: some View {
        HStack(spacing: 12) {
            Button {
                if let context = HaConfigStore.context(), let selection = ThermostatSelectionOrigin(context) {
                    thermostat.refresh(ThermostatRefreshRequest(selection: selection), source: .dashboardRefresh)
                }
                Task { await load() }
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise").frame(maxWidth: .infinity)
            }.buttonStyle(.bordered).disabled(loading)
            Button(role: .destructive, action: onSignOut) {
                Label("Sign out", systemImage: "rectangle.portrait.and.arrow.right").frame(maxWidth: .infinity)
            }.buttonStyle(.bordered)
        }
        .padding(.top, 4)
    }

    private func load() async {
        guard visible, activeConfig == config, !Task.isCancelled else { return }
        thermostat.loadCache()
        let requestID = UUID()
        loadID = requestID
        let cpRequestID = beginChargePointLoad()
        loading = true
        let now = Date(), selected = config
        await withTaskGroup(of: CardResult.self) { group in
            group.addTask { .car(await CarLiveSnapshot.fetch(now: now)) }
            group.addTask { .alarm(selected.isComplete ? await AlarmLiveSnapshot.fetch(now: now) : nil) }
            group.addTask { .chargePoint(await CpLiveSnapshot.fetchTimeline(advanceAuto: false)) }
            for await result in group {
                guard !Task.isCancelled, visible, activeConfig == selected, loadID == requestID else {
                    group.cancelAll(); return
                }
                switch result {
                case .car(let snapshot): car = snapshot
                case .alarm(let snapshot): alarm = snapshot.map { AlarmLiveSnapshot.currentFeedback($0) }
                case .chargePoint(let displays):
                    if cpLoadID == cpRequestID { publishChargePoint(displays) }
                }
            }
        }
        if !Task.isCancelled, visible, activeConfig == selected, loadID == requestID { loading = false }
    }

    private func loadChargePoint() async {
        guard visible, activeConfig == config, !Task.isCancelled else { return }
        let selected = config
        let requestID = beginChargePointLoad()
        let displays = await CpLiveSnapshot.fetchTimeline(advanceAuto: false)
        guard !Task.isCancelled, visible, activeConfig == selected, cpLoadID == requestID else { return }
        publishChargePoint(displays)
    }

    private func beginChargePointLoad() -> UUID {
        let requestID = UUID()
        cpLoadID = requestID
        cpDisplays = []
        cpLoading = true
        cpSignedIn = (try? CpSessionStore.context().session.isSignedIn) == true
        return requestID
    }

    private func publishChargePoint(_ displays: [CpTimelineDisplay]) {
        cpDisplays = displays
        displayClock = Date()
        cpSignedIn = (try? CpSessionStore.context().session.isSignedIn) == true
        cpLoading = false
    }

    private func retireLoads() {
        loadID = UUID()
        cpLoadID = UUID()
        cpDisplays = []
        cpLoading = true
    }

    private enum CardResult: Sendable {
        case car(CarSnapshot), alarm(AlarmSnapshot?), chargePoint([CpTimelineDisplay])
    }
}
