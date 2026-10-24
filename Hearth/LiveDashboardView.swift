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
    @State private var loading = true

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
                controls
            }
            .padding(20)
        }
        .background(Color(white: 0.08).ignoresSafeArea())
        .preferredColorScheme(.dark)
        .task { await load() }
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
        car = await carSnap
        alarm = await alarmSnap
        loading = false
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
