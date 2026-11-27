import SwiftUI

/// Custom toggle control — 46×28 track, 20pt thumb, ink track when on.
public struct HearthSwitch: View {
    @Binding private var isOn: Bool
    @Environment(\.colorScheme) private var colorScheme

    public init(isOn: Binding<Bool>) {
        self._isOn = isOn
    }

    public var body: some View {
        ZStack(alignment: isOn ? .trailing : .leading) {
            // Track (capsule background)
            Capsule()
                .fill(trackColor)
                .frame(width: Self.Geometry.trackWidth, height: Self.Geometry.trackHeight)

            // Thumb (circle)
            Circle()
                .fill(thumbColor)
                .frame(width: Self.Geometry.thumb, height: Self.Geometry.thumb)
                .padding(4) // 4pt inset from track edges
        }
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.2)) {
                isOn.toggle()
            }
        }
        .accessibilityAddTraits(.isToggle)
        .accessibilityValue(isOn ? "On" : "Off")
        .accessibilityAction {
            withAnimation(.easeInOut(duration: 0.2)) {
                isOn.toggle()
            }
        }
    }

    // MARK: - Colors

    /// Off-state color constants (source of truth for both body and tests).
    public struct OffStateColors {
        // Track OFF
        public static let trackOffLight: UInt32 = 0xFFD9D4CD
        public static let trackOffDark: UInt32 = 0xFF3A3835

        // Thumb OFF
        public static let thumbOffLight: UInt32 = 0xFFFFFFFF
        public static let thumbOffDark: UInt32 = 0xFF8E8981
    }

    private var trackColor: Color {
        if isOn {
            return HearthColor.ink(colorScheme)
        } else {
            return Color(argb: colorScheme == .dark ? OffStateColors.trackOffDark : OffStateColors.trackOffLight)
        }
    }

    private var thumbColor: Color {
        if isOn {
            return HearthColor.onAccent(colorScheme)
        } else {
            return Color(argb: colorScheme == .dark ? OffStateColors.thumbOffDark : OffStateColors.thumbOffLight)
        }
    }

    // MARK: - Test-Only Hooks

    public struct Geometry {
        public static let trackWidth: CGFloat = HearthMetrics.switchW
        public static let trackHeight: CGFloat = HearthMetrics.switchH
        public static let thumb: CGFloat = HearthMetrics.switchThumb
    }

    public struct TestColors {
        // Track ON
        public static let trackOnLight: UInt32 = HearthColor.inkLight
        public static let trackOnDark: UInt32 = HearthColor.inkDark

        // Track OFF (reference the source of truth)
        public static let trackOffLight: UInt32 = OffStateColors.trackOffLight
        public static let trackOffDark: UInt32 = OffStateColors.trackOffDark

        // Thumb ON (on-accent color — the page/on-ink color)
        public static let thumbOnLight: UInt32 = HearthColor.onAccentLight
        public static let thumbOnDark: UInt32 = HearthColor.onAccentDark

        // Thumb OFF (reference the source of truth)
        public static let thumbOffLight: UInt32 = OffStateColors.thumbOffLight
        public static let thumbOffDark: UInt32 = OffStateColors.thumbOffDark
    }
}

// MARK: - Preview

#Preview("HearthSwitch States") {
    struct PreviewWrapper: View {
        @State private var isOnLight = true
        @State private var isOffLight = false
        @State private var isOnDark = true
        @State private var isOffDark = false

        var body: some View {
            VStack(spacing: 24) {
                // Light mode
                VStack(spacing: 16) {
                    Text("Light Mode")
                        .font(.headline)
                    HStack(spacing: 20) {
                        VStack {
                            HearthSwitch(isOn: $isOnLight)
                            Text("ON")
                                .font(.caption)
                        }
                        VStack {
                            HearthSwitch(isOn: $isOffLight)
                            Text("OFF")
                                .font(.caption)
                        }
                    }
                }
                .padding()
                .background(Color(white: 0.95))
                .cornerRadius(HearthMetrics.chipRadius)

                // Dark mode
                VStack(spacing: 16) {
                    Text("Dark Mode")
                        .font(.headline)
                        .foregroundColor(.white)
                    HStack(spacing: 20) {
                        VStack {
                            HearthSwitch(isOn: $isOnDark)
                            Text("ON")
                                .font(.caption)
                                .foregroundColor(.white)
                        }
                        VStack {
                            HearthSwitch(isOn: $isOffDark)
                            Text("OFF")
                                .font(.caption)
                                .foregroundColor(.white)
                        }
                    }
                }
                .padding()
                .background(Color(white: 0.1))
                .cornerRadius(HearthMetrics.chipRadius)
                .environment(\.colorScheme, .dark)
            }
            .padding()
        }
    }

    return PreviewWrapper()
}
