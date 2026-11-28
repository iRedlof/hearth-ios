import SwiftUI

/// A single settings row with icon, title, subtitle, and trailing control.
/// Wraps text to support Dynamic Type and accessibility sizing.
public struct HearthRow<Trailing: View>: View {
    private let icon: String
    private let hue: TileHue
    private let title: String
    private let subtitle: String?
    private let subtitleWarn: Bool
    @ViewBuilder private let trailing: () -> Trailing

    @Environment(\.colorScheme) private var scheme

    public init(
        icon: String,
        hue: TileHue,
        title: String,
        subtitle: String? = nil,
        subtitleWarn: Bool = false,
        @ViewBuilder trailing: @escaping () -> Trailing = { EmptyView() }
    ) {
        self.icon = icon
        self.hue = hue
        self.title = title
        self.subtitle = subtitle
        self.subtitleWarn = subtitleWarn
        self.trailing = trailing
    }

    public var body: some View {
        HStack(spacing: 14) {
            IconTile(systemName: icon, hue: hue)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(HearthFont.rowTitle.font)
                    .foregroundStyle(HearthColor.ink(scheme))
                    .fixedSize(horizontal: false, vertical: true)

                if let subtitle = subtitle {
                    Text(subtitle)
                        .font(HearthFont.subtitle.font)
                        .foregroundStyle(subtitleColor)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 8)

            trailing()
        }
        .padding(.horizontal, HearthMetrics.rowSidePadding)
        .padding(.vertical, 12)
        .frame(minHeight: HearthMetrics.rowMinHeight)
        // Without a shape, a plain-style button or link around this row only reacts where something
        // is drawn (icon, text, chevron); the blank space between them was dead.
        .contentShape(Rectangle())
    }

    private var subtitleColor: Color {
        if subtitleWarn {
            return HearthColor.amber(scheme)
        } else {
            return HearthColor.sub(scheme)
        }
    }

}

// MARK: - Test-only helpers

extension HearthRow {
    /// Test-only: returns the resolved subtitle ARGB for a given warn state and scheme.
    /// Pins the rule: amber when warn, sub otherwise.
    nonisolated public static func resolvedSubtitleARGB(warn: Bool, _ scheme: ColorScheme) -> UInt32 where Trailing == EmptyView {
        if warn {
            return scheme == .light ? HearthColor.amberLight : HearthColor.amberDark
        } else {
            return scheme == .light ? HearthColor.subLight : HearthColor.subDark
        }
    }
}

// MARK: - Preview

#Preview("Connections Group — Light") {
    VStack(spacing: 20) {
        HearthGroup("Connections") {
            HearthRow(
                icon: "house",
                hue: .blue,
                title: "Home Assistant",
                subtitle: "Connected"
            ) {
                StatusPill("Connected", tone: .ok)
            }

            HearthRow(
                icon: "bolt.car",
                hue: .green,
                title: "ChargePoint",
                subtitle: "Needs sign-in",
                subtitleWarn: true
            ) {
                StatusPill("Needs sign-in", tone: .warn)
            }
        }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(HearthColor.page(.light))
    .preferredColorScheme(.light)
}

#Preview("Connections Group — Dark") {
    VStack(spacing: 20) {
        HearthGroup("Connections") {
            HearthRow(
                icon: "house",
                hue: .blue,
                title: "Home Assistant",
                subtitle: "Connected"
            ) {
                StatusPill("Connected", tone: .ok)
            }

            HearthRow(
                icon: "bolt.car",
                hue: .green,
                title: "ChargePoint",
                subtitle: "Needs sign-in",
                subtitleWarn: true
            ) {
                StatusPill("Needs sign-in", tone: .warn)
            }
        }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(HearthColor.page(.dark))
    .preferredColorScheme(.dark)
}

#Preview("Connections Group — Accessibility") {
    VStack(spacing: 20) {
        HearthGroup("Connections") {
            HearthRow(
                icon: "house",
                hue: .blue,
                title: "Home Assistant",
                subtitle: "Connected"
            ) {
                StatusPill("Connected", tone: .ok)
            }

            HearthRow(
                icon: "bolt.car",
                hue: .green,
                title: "ChargePoint",
                subtitle: "Needs sign-in",
                subtitleWarn: true
            ) {
                StatusPill("Needs sign-in", tone: .warn)
            }
        }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(HearthColor.page(.light))
    .environment(\.sizeCategory, .accessibilityExtraLarge)
    .preferredColorScheme(.light)
}
