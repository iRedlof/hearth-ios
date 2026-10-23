import SwiftUI

@main
struct HearthApp: App {
    var body: some Scene {
        WindowGroup { ContentView() }
    }
}

/// For now the app is a verification gallery: it renders the Car Beacon widget view at the
/// medium-widget size across device widths, so the design can be checked in the Simulator
/// without adding a real home-screen widget (that needs signing + manual placement).
struct ContentView: View {
    var body: some View {
        WidgetGalleryView()
    }
}
