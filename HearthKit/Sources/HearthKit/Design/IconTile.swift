import SwiftUI

// MARK: - TileHue

/// Jewel-tone hue for icon tiles, ported verbatim from Android SettingsKit.kt.
public enum TileHue: String, CaseIterable {
    case blue, orange, purple, green, red, amber, neutral

    /// Fill ARGB for the given color scheme.
    public func fillARGB(_ scheme: ColorScheme) -> UInt32 {
        switch (self, scheme) {
        case (.blue, .light):    return 0xFFDDEBFA
        case (.blue, .dark):     return 0xFF1D3247
        case (.orange, .light):  return 0xFFFCE3CF
        case (.orange, .dark):   return 0xFF43281A
        case (.purple, .light):  return 0xFFEAE3FB
        case (.purple, .dark):   return 0xFF2E2648
        case (.green, .light):   return 0xFFDDF0E3
        case (.green, .dark):    return 0xFF1C3526
        case (.red, .light):     return 0xFFFBDDDD
        case (.red, .dark):      return 0xFF452023
        case (.amber, .light):   return 0xFFFBEED3
        case (.amber, .dark):    return 0xFF3F3015
        case (.neutral, .light): return 0xFFECE8E2
        case (.neutral, .dark):  return 0xFF34312E
        @unknown default:        return 0xFFECE8E2
        }
    }

    /// Ink ARGB for the given color scheme.
    public func inkARGB(_ scheme: ColorScheme) -> UInt32 {
        switch (self, scheme) {
        case (.blue, .light):    return 0xFF1F4E79
        case (.blue, .dark):     return 0xFF9CC6F0
        case (.orange, .light):  return 0xFF8A3A0A
        case (.orange, .dark):   return 0xFFF4B48A
        case (.purple, .light):  return 0xFF4B348F
        case (.purple, .dark):   return 0xFFC4B3F5
        case (.green, .light):   return 0xFF1F5C36
        case (.green, .dark):    return 0xFF94D2AA
        case (.red, .light):     return 0xFF8C1D1D
        case (.red, .dark):      return 0xFFF2A3A3
        case (.amber, .light):   return 0xFF7A4A00
        case (.amber, .dark):    return 0xFFF0C873
        case (.neutral, .light): return 0xFF4A4540
        case (.neutral, .dark):  return 0xFFD3CCC4
        @unknown default:        return 0xFF4A4540
        }
    }

    /// Fill color resolved for the given scheme.
    public func fill(_ scheme: ColorScheme) -> Color {
        Color(argb: fillARGB(scheme))
    }

    /// Ink color resolved for the given scheme.
    public func ink(_ scheme: ColorScheme) -> Color {
        Color(argb: inkARGB(scheme))
    }
}

// MARK: - IconTile

/// A rounded-square icon tile with an SF Symbol, using jewel-tone hues.
public struct IconTile: View {
    @Environment(\.colorScheme) private var colorScheme

    private let systemName: String
    private let hue: TileHue

    public init(systemName: String, hue: TileHue) {
        self.systemName = systemName
        self.hue = hue
    }

    public var body: some View {
        RoundedRectangle(cornerRadius: HearthMetrics.iconTileRadius)
            .fill(hue.fill(colorScheme))
            .frame(width: HearthMetrics.iconTile, height: HearthMetrics.iconTile)
            .overlay(
                Image(systemName: systemName)
                    .font(HearthFont.iconMedium.font)
                    .foregroundStyle(hue.ink(colorScheme))
            )
    }
}

// MARK: - Preview

#Preview("Icon Tiles") {
    VStack(spacing: 16) {
        Text("Light Mode")
            .font(.headline)
        HStack(spacing: 12) {
            ForEach(TileHue.allCases, id: \.self) { hue in
                IconTile(systemName: "heart.fill", hue: hue)
            }
        }

        Divider()

        Text("Dark Mode")
            .font(.headline)
        HStack(spacing: 12) {
            ForEach(TileHue.allCases, id: \.self) { hue in
                IconTile(systemName: "heart.fill", hue: hue)
            }
        }
        .preferredColorScheme(.dark)
    }
    .padding()
}
