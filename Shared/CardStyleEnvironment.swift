import SwiftUI
import HearthKit

/// Environment key for CardStyle propagation through widget content.
private struct CardStyleKey: EnvironmentKey {
    static let defaultValue: CardStyle = .default
}

extension EnvironmentValues {
    var cardStyle: CardStyle {
        get { self[CardStyleKey.self] }
        set { self[CardStyleKey.self] = newValue }
    }
}

extension View {
    /// Applies CardStyle text scaling to this view's fonts.
    /// Wraps the view in a container that scales all fonts by the given factor.
    func cardTextScaled(_ scale: CGFloat) -> some View {
        self.environment(\.sizeCategory, scaledSizeCategory(scale))
    }

    /// Provides CardStyle for child views.
    func cardStyle(_ style: CardStyle) -> some View {
        self.environment(\.cardStyle, style)
    }
}

/// Maps a scale factor to an approximate ContentSizeCategory adjustment.
/// Not perfect, but works for the .9 / 1.0 / 1.12 range.
private func scaledSizeCategory(_ scale: CGFloat) -> ContentSizeCategory {
    if scale < 0.95 {
        return .small  // smaller
    } else if scale > 1.05 {
        return .extraLarge  // larger
    } else {
        return .large  // normal
    }
}
