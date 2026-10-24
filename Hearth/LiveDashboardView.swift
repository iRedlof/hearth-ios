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
        .task { await load() }
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
        loading = true
        let now = Date()
        async let carSnap = fetchCar(now)
        async let alarmSnap = fetchAlarmMaybe(now)
        async let thermoSnap = fetchThermostatMaybe(now)
        async let cpSnap = fetchCpMaybe(now)
        car = await carSnap
        alarm = await alarmSnap
        thermostat = await thermoSnap
        cp = await cpSnap
        loading = false
    }

    private func fetchThermostatMaybe(_ now: Date) async -> ThermostatSnapshot? {
        guard config.hasClimate else { return nil }
        return await fetchThermostatSnapshot(config, now: now)
    }

    private func fetchCpMaybe(_ now: Date) async -> CpSnapshot {
        let session = CpSessionStore.load()
        let run = CpSessionStore.loadRun()
        return await fetchCpSnapshot(session, onToken: { CpSessionStore.saveToken($0) }, autoOn: run.armed, now: now)
    }

    private func fetchCar(_ now: Date) async -> CarSnapshot? {
        do {
            let json = try await HaClient(config).template(CAR_TEMPLATE)
            return carSnapshot(carFromTemplate(json), now: now, stale: false, checkedAt: now)
        } catch { return nil }
    }

    private func fetchAlarmMaybe(_ now: Date) async -> AlarmSnapshot? {
        guard config.isComplete else { return nil }
        return await fetchAlarmSnapshot(config, now: now)
    }
}
