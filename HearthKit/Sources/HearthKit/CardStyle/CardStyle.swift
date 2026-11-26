import Foundation
import SwiftUI

/// Named gradient colours for card backgrounds (iOS-portable subset).
/// Each maps to a gradient fill with light/dark variants.
public enum CardColour: String, CaseIterable, Sendable, Codable {
    case ocean
    case night
    case plum
    case rose
    case forest
    case slate
    case graphite
    case snow

    /// Returns the ARGB fill colour for this card colour in the given colour scheme.
    /// Uses the top gradient colour from Android CardStyle.kt.
    public func fillARGB(_ scheme: ColorScheme) -> UInt32 {
        switch (self, scheme) {
        case (.ocean, .light): return 0xFF1D8FB4
        case (.ocean, .dark): return 0xFF0A3C58
        case (.night, .light): return 0xFF2B3A67
        case (.night, .dark): return 0xFF121A33
        case (.plum, .light): return 0xFF5B4B8A
        case (.plum, .dark): return 0xFF2A1F4A
        case (.rose, .light): return 0xFFB4536E
        case (.rose, .dark): return 0xFF5A1E33
        case (.forest, .light): return 0xFF4F7A3A
        case (.forest, .dark): return 0xFF1F3519
        case (.slate, .light): return 0xFF5A6474
        case (.slate, .dark): return 0xFF262B33
        case (.graphite, .light): return 0xFF3A3C42
        case (.graphite, .dark): return 0xFF18191C
        case (.snow, .light): return 0xFFF4F5F7
        case (.snow, .dark): return 0xFFD9DDE3
        @unknown default: return 0xFF3A3C42 // fallback to graphite light
        }
    }
}

/// Card background choice (iOS-portable subset: no Glass/Wallpaper).
public enum CardBackground: Sendable, Codable, Equatable {
    /// Use the widget's state colour (default beacon tone).
    case byState
    /// Use a specific named colour.
    case colour(CardColour)
    /// Solid black background.
    case black
}

/// Text size scale for card content (on top of system dynamic type).
public enum CardTextSize: String, CaseIterable, Sendable, Codable {
    case smaller
    case normal
    case larger

    /// Scale factor applied to base font sizes.
    public var scale: CGFloat {
        switch self {
        case .smaller: return 0.9
        case .normal: return 1.0
        case .larger: return 1.12
        }
    }
}

/// Card styling preferences (iOS-portable axes only).
/// Omits Corners/Glass/Wallpaper — WidgetKit controls the container shape+background.
public struct CardStyle: Sendable, Codable, Equatable {
    public var background: CardBackground
    public var textSize: CardTextSize
    /// Whether to show small print (secondary lines like "Checked 9:41 AM").
    public var smallPrint: Bool

    /// Default style: by-state background, normal text, small print on.
    public static let `default` = CardStyle(
        background: .byState,
        textSize: .normal,
        smallPrint: true
    )

    public init(background: CardBackground, textSize: CardTextSize, smallPrint: Bool) {
        self.background = background
        self.textSize = textSize
        self.smallPrint = smallPrint
    }
}

/// Pure resolution logic for effective style (global + optional override).
/// Used by CardStyleStore; testable without UserDefaults.
public func resolveStyle(global: CardStyle, override: CardStyle?) -> CardStyle {
    override ?? global
}
