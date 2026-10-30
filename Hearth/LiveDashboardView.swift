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
    @State private var thermostat: ThermostatSnapshot?
    @State private var cp: CpSnapshot?
    @State private var cpSignedIn = CpSessionStore.load().isSignedIn
    @State private var showCpSignIn = false
    @State private var loading = true
    @State private var loadID = UUID()
    @ObservedObject private var refreshSignal = RefreshSignal.shared

    var body: some View {
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
                    card { if let thermostat { ThermostatBeaconView(thermostat) } else { placeholder } }
                }
                sectionTitle("ChargePoint")
                card { if let cp { CpBeaconView(cp) } else { placeholder } }
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
        .task(id: config) { await load() }
        .onChange(of: refreshSignal.tick) { Task { await load() } }
        .sheet(isPresented: $showCpSignIn) {
            NavigationStack {
                CpSignInView(onSignedIn: {
                    showCpSignIn = false
                    cpSignedIn = CpSessionStore.load().isSignedIn
                    Task { await load() }
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

    private func card<V: View>(@ViewBuilder _ content: () -> V) -> some View {
        content()
            .frame(height: 174).frame(maxWidth: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .shadow(color: .black.opacity(0.25), radius: 6, y: 3)
            .opacity(loading ? 0.5 : 1)   // dim while a refresh is in flight
    }

    private var placeholder: some View {
        ZStack { Color(white: 0.12); ProgressView() }
    }

    private var controls: some View {
        HStack(spacing: 12) {
            Button { Task { await load() } } label: {
                Label("Refresh", systemImage: "arrow.clockwise").frame(maxWidth: .infinity)
            }.buttonStyle(.bordered).disabled(loading)
            Button(role: .destructive, action: onSignOut) {
                Label("Sign out", systemImage: "rectangle.portrait.and.arrow.right").frame(maxWidth: .infinity)
            }.buttonStyle(.bordered)
        }
        .padding(.top, 4)
    }

    private func load() async {
        let requestID = UUID()
        loadID = requestID
        loading = true
        let now = Date(), selected = config
        await withTaskGroup(of: CardResult.self) { group in
            group.addTask { .car(await CarLiveSnapshot.fetch(now: now)) }
            group.addTask { .alarm(selected.isComplete ? await AlarmLiveSnapshot.fetch(now: now) : nil) }
            group.addTask { .thermostat(selected.hasClimate ? await ThermostatLiveSnapshot.fetch(now: now) : nil) }
            group.addTask { .chargePoint(await CpLiveSnapshot.fetch(now: now)) }
            for await result in group {
                guard !Task.isCancelled, loadID == requestID else { group.cancelAll(); return }
                switch result {
                case .car(let snapshot): car = snapshot
                case .alarm(let snapshot): alarm = snapshot.map { AlarmLiveSnapshot.currentFeedback($0) }
                case .thermostat(let snapshot): thermostat = snapshot.map { ThermostatLiveSnapshot.currentFeedback($0) }
                case .chargePoint(let snapshot): cp = snapshot
                }
            }
        }
        if loadID == requestID { loading = false }
    }

    private enum CardResult: Sendable {
        case car(CarSnapshot), alarm(AlarmSnapshot?), thermostat(ThermostatSnapshot?), chargePoint(CpSnapshot)
    }
}
