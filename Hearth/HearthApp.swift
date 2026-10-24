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

    var body: some View {
        TabView {
            liveTab
                .tabItem { Label("Live", systemImage: "car.fill") }
            WidgetGalleryView()
                .tabItem { Label("Preview", systemImage: "square.grid.2x2.fill") }
        }
    }

    @ViewBuilder private var liveTab: some View {
        if let config, config.carReady {
            LiveCarView(config: config, onSignOut: signOut)
        } else {
            SignInView(onSignedIn: { config = HaConfigStore.load() })
        }
    }

    private func signOut() {
        HaConfigStore.clear()
        Task { await HaAuth.shared.forget() }
        WidgetCenter.shared.reloadAllTimelines()
        config = nil
    }
}
