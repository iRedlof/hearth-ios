import Foundation

/// The Beacon status palette, ported verbatim from the Android app (`BeaconMetrics.kt`).
/// A tone carries a `fill` (the light rail/left-panel colour) and an `ink` (readable on that fill).
/// Colours are ARGB hex; the SwiftUI layer converts to `Color`.
public enum BeaconTone: String, Sendable, CaseIterable {
    case mint, blue, red, yellow, offline, triggered

    public var fillARGB: UInt32 {
        switch self {
        case .mint:      return 0xFFB6D9C1
        case .blue:      return 0xFFA6D5FF
        case .red:       return 0xFFF2A0A4
        case .yellow:    return 0xFFF6D58A
        case .offline:   return 0xFFBCC2B9
        case .triggered: return 0xFFF49283   // the alarm's distinct "triggered" red (BeaconMetrics.kt)
        }
    }

    public var inkARGB: UInt32 {
        switch self {
        case .mint:      return 0xFF244232
        case .blue:      return 0xFF1C3B53
        case .red:       return 0xFF4D2029
        case .yellow:    return 0xFF493614
        case .offline:   return 0xFF29342D
        case .triggered: return 0xFF491D21
        }
    }
}

/// The graphite "surface" (the dark right panel) and its text inks, from the car card's dark card look.
/// `ink` is the bright header colour; `soft` is the dim secondary (now only used where intended).
public enum BeaconSurfaceColors {
    public static let graphiteARGB: UInt32 = 0xFF262B27
    public static let inkARGB: UInt32      = 0xFFEEF3F0   // bright, readable on graphite (the header colour)
    public static let softARGB: UInt32     = 0xFFACBAB2   // dim secondary
    public static let raisedARGB: UInt32   = 0x1FFFFFFF   // ~12% white, the raised button fill
    /// Sentry-ON attention colour (v1.4.28): light red on the dark panel.
    public static let sentryOnARGB: UInt32 = 0xFFF2A0A4
}
