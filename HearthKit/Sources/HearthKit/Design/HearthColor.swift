import SwiftUI

/// Warm color palette tokens for Hearth — pure cross-platform values.
/// Each token exposes light and dark ARGB constants, plus a ColorScheme-based helper.
///
/// Convention: HearthColor is the raw light/dark constant store plus `token(_ scheme:)` Color accessors.
/// Mapper types (StatusTone, TileHue) expose `*ARGB(_ scheme:)` raw hooks and Color accessors for testability.
public enum HearthColor {

    // MARK: - ARGB Constants

    // Page (warmest background)
    public static let pageLight: UInt32 = 0xFFF5F3EF
    public static let pageDark: UInt32 = 0xFF111110

    // Card (elevated surface)
    public static let cardLight: UInt32 = 0xFFFFFFFF
    public static let cardDark: UInt32 = 0xFF1D1C1B

    // Tint (subtle surface variant)
    public static let tintLight: UInt32 = 0xFFEFEBE5
    public static let tintDark: UInt32 = 0xFF282624

    // Line (borders, dividers)
    public static let lineLight: UInt32 = 0xFFECE8E2
    public static let lineDark: UInt32 = 0xFF2A2826

    // Ink (primary text)
    public static let inkLight: UInt32 = 0xFF1C1B19
    public static let inkDark: UInt32 = 0xFFF2EFEA

    // Sub (secondary text)
    public static let subLight: UInt32 = 0xFF736D66
    public static let subDark: UInt32 = 0xFF9F988F

    // Mute (tertiary text)
    public static let muteLight: UInt32 = 0xFFA49D95
    public static let muteDark: UInt32 = 0xFF6C665F

    // Green (success, positive)
    public static let greenLight: UInt32 = 0xFF2E7D4F
    public static let greenDark: UInt32 = 0xFF7FD3A0

    // Green background
    public static let greenBgLight: UInt32 = 0xFFE2F2E7
    public static let greenBgDark: UInt32 = 0xFF15301F

    // Amber (warning, attention)
    public static let amberLight: UInt32 = 0xFFA85F00
    public static let amberDark: UInt32 = 0xFFFFB54D

    // Amber background
    public static let amberBgLight: UInt32 = 0xFFFFF0D9
    public static let amberBgDark: UInt32 = 0xFF38270F

    // Red (error, critical)
    public static let redLight: UInt32 = 0xFFB3261E
    public static let redDark: UInt32 = 0xFFF2B8B5

    // Accent (alias to ink for primary actions)
    public static let accentLight: UInt32 = inkLight
    public static let accentDark: UInt32 = inkDark

    // On-accent (text on accent backgrounds, alias to page)
    public static let onAccentLight: UInt32 = pageLight
    public static let onAccentDark: UInt32 = pageDark

    // Widget preview background (warm accent for widget preview cards)
    public static let widgetPreviewBgLight: UInt32 = 0xFFFFD4B3
    public static let widgetPreviewBgDark: UInt32 = 0xFF3D2F28

    // Placeholder background (for unimplemented widget previews)
    public static let placeholderBgLight: UInt32 = 0xFF2A2D2E
    public static let placeholderBgDark: UInt32 = 0xFF2A2D2E

    // MARK: - ColorScheme Helpers

    public static func page(_ scheme: ColorScheme) -> Color {
        Color(argb: scheme == .dark ? pageDark : pageLight)
    }

    public static func card(_ scheme: ColorScheme) -> Color {
        Color(argb: scheme == .dark ? cardDark : cardLight)
    }

    public static func tint(_ scheme: ColorScheme) -> Color {
        Color(argb: scheme == .dark ? tintDark : tintLight)
    }

    public static func line(_ scheme: ColorScheme) -> Color {
        Color(argb: scheme == .dark ? lineDark : lineLight)
    }

    public static func ink(_ scheme: ColorScheme) -> Color {
        Color(argb: scheme == .dark ? inkDark : inkLight)
    }

    public static func sub(_ scheme: ColorScheme) -> Color {
        Color(argb: scheme == .dark ? subDark : subLight)
    }

    public static func mute(_ scheme: ColorScheme) -> Color {
        Color(argb: scheme == .dark ? muteDark : muteLight)
    }

    public static func green(_ scheme: ColorScheme) -> Color {
        Color(argb: scheme == .dark ? greenDark : greenLight)
    }

    public static func greenBg(_ scheme: ColorScheme) -> Color {
        Color(argb: scheme == .dark ? greenBgDark : greenBgLight)
    }

    public static func amber(_ scheme: ColorScheme) -> Color {
        Color(argb: scheme == .dark ? amberDark : amberLight)
    }

    public static func amberBg(_ scheme: ColorScheme) -> Color {
        Color(argb: scheme == .dark ? amberBgDark : amberBgLight)
    }

    public static func red(_ scheme: ColorScheme) -> Color {
        Color(argb: scheme == .dark ? redDark : redLight)
    }

    public static func accent(_ scheme: ColorScheme) -> Color {
        Color(argb: scheme == .dark ? accentDark : accentLight)
    }

    public static func onAccent(_ scheme: ColorScheme) -> Color {
        Color(argb: scheme == .dark ? onAccentDark : onAccentLight)
    }

    public static func widgetPreviewBg(_ scheme: ColorScheme) -> Color {
        Color(argb: scheme == .dark ? widgetPreviewBgDark : widgetPreviewBgLight)
    }

    public static func placeholderBg(_ scheme: ColorScheme) -> Color {
        Color(argb: scheme == .dark ? placeholderBgDark : placeholderBgLight)
    }
}

// MARK: - Color ARGB Extension

public extension Color {
    /// Build a Color from a 0xAARRGGBB value.
    init(argb: UInt32) {
        let a = Double((argb >> 24) & 0xFF) / 255.0
        let r = Double((argb >> 16) & 0xFF) / 255.0
        let g = Double((argb >> 8) & 0xFF) / 255.0
        let b = Double(argb & 0xFF) / 255.0
        self = Color(.sRGB, red: r, green: g, blue: b, opacity: a)
    }
}
