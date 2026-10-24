import SwiftUI
import WidgetKit
import HearthKit

/// The "Live" tab: fetches the real car state from Home Assistant (a single `POST /api/template`
/// with the auto-discovery `CAR_TEMPLATE`) and renders it through the *same* `CarBeaconView` the
/// home-screen widget uses — so what you see here is exactly what the widget shows. On failure it
/// shows a friendly line with Retry / Sign out.
struct LiveCarView: View {
    let config: HaConfig
    var onSignOut: () -> Void

    @State private var snap: CarSnapshot?
    @State private var error: String?
    @State private var loading = true

    var body: some View {
        VStack(spacing: 18) {
            header
            content
            controls
            Spacer()
        }
        .padding(20)
        .background(Color(white: 0.08).ignoresSafeArea())
        .preferredColorScheme(.dark)
        .task { await load() }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Live").font(.title3.weight(.bold))
                Text(config.baseUrl)
                    .font(.caption2).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            }
            Spacer()
        }
    }

    @ViewBuilder private var content: some View {
        if loading && snap == nil {
            ProgressView("Checking your car…")
                .frame(maxWidth: .infinity, minHeight: 174)
        } else if let snap {
            CarBeaconView(snap)
                .frame(height: 174)
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                .shadow(color: .black.opacity(0.25), radius: 6, y: 3)
                .opacity(loading ? 0.5 : 1)      // dim while a refresh is in flight
        } else {
            errorCard
        }
    }

    @ViewBuilder private var errorCard: some View {
        VStack(spacing: 8) {
            Image(systemName: "car.fill").font(.largeTitle).foregroundStyle(.secondary)
            Text("Couldn't load your car").font(.headline)
            if let error {
                Text(error)
                    .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 174)
    }

    private var controls: some View {
        HStack(spacing: 12) {
            Button { Task { await load() } } label: {
                Label("Refresh", systemImage: "arrow.clockwise").frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(loading)

            Button(role: .destructive, action: onSignOut) {
                Label("Sign out", systemImage: "rectangle.portrait.and.arrow.right").frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
    }

    private func load() async {
        loading = true
        error = nil
        do {
            let json = try await HaClient(config).template(CAR_TEMPLATE)
            let now = Date()
            // `carFromTemplate` returns nil when no car is discovered; `carSnapshot` turns that into a
            // tidy "No car found" card rather than an error, matching the Android behaviour.
            snap = carSnapshot(carFromTemplate(json), now: now, stale: false, checkedAt: now)
        } catch {
            self.error = friendlyError(error)
            snap = nil
        }
        loading = false
    }
}
