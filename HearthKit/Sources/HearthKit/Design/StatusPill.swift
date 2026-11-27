import SwiftUI

/// Status tone for health/warning/neutral states.
/// Each tone maps to a background and ink color pair.
public enum StatusTone: Sendable {
    case ok      // healthy state → green
    case warn    // fixable problem → amber
    case neutral // informational → grey

    /// Returns the background color for this tone in the given color scheme.
    public func bg(_ scheme: ColorScheme) -> Color {
        switch self {
        case .ok:
            return HearthColor.greenBg(scheme)
        case .warn:
            return HearthColor.amberBg(scheme)
        case .neutral:
            return HearthColor.tint(scheme)
        }
    }

    /// Returns the ink (foreground) color for this tone in the given color scheme.
    public func ink(_ scheme: ColorScheme) -> Color {
        switch self {
        case .ok:
            return HearthColor.green(scheme)
        case .warn:
            return HearthColor.amber(scheme)
        case .neutral:
            return HearthColor.mute(scheme)
        }
    }

    // MARK: - Test Hooks (macOS-safe, no Color equality)

    /// Returns the raw ARGB value for the background color in the given scheme.
    public func bgARGB(_ scheme: ColorScheme) -> UInt32 {
        switch self {
        case .ok:
            return scheme == .dark ? HearthColor.greenBgDark : HearthColor.greenBgLight
        case .warn:
            return scheme == .dark ? HearthColor.amberBgDark : HearthColor.amberBgLight
        case .neutral:
            return scheme == .dark ? HearthColor.tintDark : HearthColor.tintLight
        }
    }

    /// Returns the raw ARGB value for the ink color in the given scheme.
    public func inkARGB(_ scheme: ColorScheme) -> UInt32 {
        switch self {
        case .ok:
            return scheme == .dark ? HearthColor.greenDark : HearthColor.greenLight
        case .warn:
            return scheme == .dark ? HearthColor.amberDark : HearthColor.amberLight
        case .neutral:
            return scheme == .dark ? HearthColor.muteDark : HearthColor.muteLight
        }
    }
}

/// A small status pill with a leading dot and text label.
/// Used to display health/warning/neutral states across the app.
public struct StatusPill: View {
    private let text: String
    private let tone: StatusTone
    @Environment(\.colorScheme) private var colorScheme

    public init(_ text: String, tone: StatusTone) {
        self.text = text
        self.tone = tone
    }

    public var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(tone.ink(colorScheme))
                .frame(width: 6, height: 6)

            Text(text)
                .font(HearthFont.pill.font)
                .foregroundStyle(tone.ink(colorScheme))
                .minimumScaleFactor(0.8)
                .lineLimit(2)
        }
        .padding(.horizontal, 12)
        .frame(minHeight: HearthMetrics.chipH)
        .background(
            Capsule()
                .fill(tone.bg(colorScheme))
        )
    }
}

// MARK: - Previews

#Preview("Status Pills - Light") {
    VStack(spacing: 16) {
        StatusPill("Online", tone: .ok)
        StatusPill("Needs attention", tone: .warn)
        StatusPill("Offline", tone: .neutral)
    }
    .padding()
    .preferredColorScheme(.light)
}

#Preview("Status Pills - Dark") {
    VStack(spacing: 16) {
        StatusPill("Online", tone: .ok)
        StatusPill("Needs attention", tone: .warn)
        StatusPill("Offline", tone: .neutral)
    }
    .padding()
    .preferredColorScheme(.dark)
}
