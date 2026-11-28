import SwiftUI

// MARK: - Hero Presentation

/// Presentation model for the ConnectionHero status display.
public struct HeroPresentation: Sendable, Equatable {
    public let tone: StatusTone
    public let word: String
    public let icon: String

    public init(tone: StatusTone, word: String, icon: String) {
        self.tone = tone
        self.word = word
        self.icon = icon
    }
}

// MARK: - Home Assistant Presentation Mappers

/// Maps Home Assistant connection status to hero presentation.
public func haHeroPresentation(_ status: HaConnectionStatus) -> HeroPresentation {
    switch status {
    case .connected:
        return HeroPresentation(tone: .ok, word: "Connected", icon: "checkmark.circle.fill")
    case .needsSignIn:
        return HeroPresentation(tone: .warn, word: "Needs sign-in", icon: "lock.fill")
    case .notSetUp:
        return HeroPresentation(tone: .neutral, word: "Not set up", icon: "house.fill")
    }
}

/// Returns the offline presentation for Home Assistant.
public func haHeroOffline() -> HeroPresentation {
    HeroPresentation(tone: .neutral, word: "Offline", icon: "cloud.slash.fill")
}

/// Returns the connection check OK presentation for Home Assistant.
public func haHeroCheckOK() -> HeroPresentation {
    HeroPresentation(tone: .ok, word: "Connection OK", icon: "checkmark.circle.fill")
}

// MARK: - ChargePoint Presentation Mappers

/// Maps ChargePoint connection status to hero presentation.
public func cpHeroPresentation(_ status: CpConnectionStatus) -> HeroPresentation {
    switch status {
    case .connected:
        return HeroPresentation(tone: .ok, word: "Connected", icon: "checkmark.circle.fill")
    case .needsSignIn:
        return HeroPresentation(tone: .warn, word: "Needs sign-in", icon: "lock.fill")
    case .notSetUp:
        return HeroPresentation(tone: .neutral, word: "Not set up", icon: "bolt.car.fill")
    }
}

// MARK: - ConnectionHero View

/// A split hero card showing connection status with a tinted status panel and a dark CTA panel.
/// Used atop Home Assistant and ChargePoint settings pages.
public struct ConnectionHero<Side: View>: View {
    private let presentation: HeroPresentation
    private let title: String
    private let detail: String
    private let side: Side
    private let showsSide: Bool

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    public init(
        presentation: HeroPresentation,
        title: String,
        detail: String,
        showsSide: Bool = true,
        @ViewBuilder side: () -> Side
    ) {
        self.presentation = presentation
        self.title = title
        self.detail = detail
        self.showsSide = showsSide
        self.side = side()
    }

    public var body: some View {
        let isCompact = horizontalSizeClass == .compact

        if isCompact {
            // Vertical stack for phone widths
            VStack(spacing: Self.panelGap) {
                statusPanel
                // No button, no button area: an empty panel left a blank strip under the status.
                if showsSide { ctaPanel }
            }
            .padding(Self.cardPadding)
            .background(HearthColor.card(colorScheme))
            .clipShape(RoundedRectangle(cornerRadius: HearthMetrics.groupRadius))
        } else {
            // Horizontal split for wider screens
            HStack(spacing: Self.panelGap) {
                statusPanel
                    .frame(maxWidth: .infinity)

                if showsSide {
                    ctaPanel
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(Self.cardPadding)
            .background(HearthColor.card(colorScheme))
            .clipShape(RoundedRectangle(cornerRadius: HearthMetrics.groupRadius))
        }
    }

    // MARK: - Status Panel

    private var statusPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: presentation.icon)
                .font(HearthFont.largeTitle.font.weight(.medium))
                .foregroundStyle(presentation.tone.ink(colorScheme))

            Text(presentation.word)
                .font(HearthFont.cardHeading.font)
                .foregroundStyle(presentation.tone.ink(colorScheme))

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(HearthFont.subtitle.font)
                    .foregroundStyle(presentation.tone.ink(colorScheme).opacity(0.8))

                Text(detail)
                    .font(HearthFont.subtitle.font)
                    .foregroundStyle(presentation.tone.ink(colorScheme).opacity(0.6))
            }
        }
        // The text sits inside the tinted panel. Without this inset the panel hugged the text and
        // its rounded corners cut into the icon and the last line.
        .padding(Self.panelPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(presentation.tone.bg(colorScheme))
        .clipShape(RoundedRectangle(cornerRadius: HearthMetrics.groupRadius))
    }

    private static var cardPadding: CGFloat { 12 }
    private static var panelPadding: CGFloat { 16 }
    private static var panelGap: CGFloat { 12 }

    // MARK: - CTA Panel

    private var ctaPanel: some View {
        VStack(alignment: .center) {
            side
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(HearthColor.ink(colorScheme))
        .clipShape(RoundedRectangle(cornerRadius: HearthMetrics.groupRadius))
    }
}

// MARK: - Previews

#Preview("Connected - Light") {
    ConnectionHero(
        presentation: haHeroPresentation(.connected),
        title: "Home Assistant",
        detail: "Last synced 2 minutes ago"
    ) {
        Button("Check connection") {}
            .hearthInk()
    }
    .padding()
    .frame(maxWidth: 500)
    .preferredColorScheme(.light)
}

#Preview("Connected - Dark") {
    ConnectionHero(
        presentation: haHeroPresentation(.connected),
        title: "Home Assistant",
        detail: "Last synced 2 minutes ago"
    ) {
        Button("Check connection") {}
            .hearthInk()
    }
    .padding()
    .frame(maxWidth: 500)
    .preferredColorScheme(.dark)
}

#Preview("Needs Sign-in - Light") {
    ConnectionHero(
        presentation: haHeroPresentation(.needsSignIn),
        title: "Home Assistant",
        detail: "Session expired"
    ) {
        Button("Sign in again") {}
            .hearthInk()
    }
    .padding()
    .frame(maxWidth: 500)
    .preferredColorScheme(.light)
}

#Preview("Needs Sign-in - Dark") {
    ConnectionHero(
        presentation: haHeroPresentation(.needsSignIn),
        title: "Home Assistant",
        detail: "Session expired"
    ) {
        Button("Sign in again") {}
            .hearthInk()
    }
    .padding()
    .frame(maxWidth: 500)
    .preferredColorScheme(.dark)
}

#Preview("Offline - Light") {
    ConnectionHero(
        presentation: haHeroOffline(),
        title: "Home Assistant",
        detail: "Could not reach server"
    ) {
        Button("Try again") {}
            .hearthInk()
    }
    .padding()
    .frame(maxWidth: 500)
    .preferredColorScheme(.light)
}

#Preview("Offline - Dark") {
    ConnectionHero(
        presentation: haHeroOffline(),
        title: "Home Assistant",
        detail: "Could not reach server"
    ) {
        Button("Try again") {}
            .hearthInk()
    }
    .padding()
    .frame(maxWidth: 500)
    .preferredColorScheme(.dark)
}

#Preview("Not Set Up - Light") {
    ConnectionHero(
        presentation: haHeroPresentation(.notSetUp),
        title: "Home Assistant",
        detail: "No server configured"
    ) {
        Button("Connect") {}
            .hearthInk()
    }
    .padding()
    .frame(maxWidth: 500)
    .preferredColorScheme(.light)
}

#Preview("Not Set Up - Dark") {
    ConnectionHero(
        presentation: haHeroPresentation(.notSetUp),
        title: "Home Assistant",
        detail: "No server configured"
    ) {
        Button("Connect") {}
            .hearthInk()
    }
    .padding()
    .frame(maxWidth: 500)
    .preferredColorScheme(.dark)
}

#Preview("ChargePoint - Light") {
    ConnectionHero(
        presentation: cpHeroPresentation(.connected),
        title: "ChargePoint",
        detail: "Active session"
    ) {
        Button("View stations") {}
            .hearthInk()
    }
    .padding()
    .frame(maxWidth: 500)
    .preferredColorScheme(.light)
}

#Preview("ChargePoint - Dark") {
    ConnectionHero(
        presentation: cpHeroPresentation(.connected),
        title: "ChargePoint",
        detail: "Active session"
    ) {
        Button("View stations") {}
            .hearthInk()
    }
    .padding()
    .frame(maxWidth: 500)
    .preferredColorScheme(.dark)
}
