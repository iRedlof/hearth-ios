import SwiftUI
import HearthKit

private struct CardStyleKey: EnvironmentKey {
    static let defaultValue = CardStyle.default
}

extension EnvironmentValues {
    /// The Card style the enclosing widget card draws with. Every widget view reads it from here,
    /// so the Home Screen widget, the in-app previews and the parity fixtures share one path.
    var cardStyle: CardStyle {
        get { self[CardStyleKey.self] }
        set { self[CardStyleKey.self] = newValue }
    }

    /// What every text in the card is multiplied by (Android `BeaconChrome.kt:188`, `ts()`).
    var cardTextScale: CGFloat { cardStyle.textSize.scale }
}

extension View {
    /// Draws the widget card inside this view in `style`.
    func cardStyle(_ style: CardStyle) -> some View {
        environment(\.cardStyle, style)
    }
}
