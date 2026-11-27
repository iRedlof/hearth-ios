import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Type ramp for Hearth design system using Roboto Flex variable font.
/// Scales with Dynamic Type via `relativeTo` text styles.
public enum HearthFont {
    /// Large title: 34pt, weight 450
    case largeTitle
    /// Hero large: 52pt, weight 450 (extra large displays)
    case heroLarge
    /// Icon hero: 48pt, weight 450 (large icons)
    case iconHero
    /// Title3: 24pt, weight 450
    case title3
    /// Page title: 22pt, weight 450
    case pageTitle
    /// Card heading: 19pt, weight 450
    case cardHeading
    /// Row title: 15pt, regular weight (400)
    case rowTitle
    /// Callout: 14pt, regular weight (400)
    case callout
    /// Group label: 13pt, weight 550
    case groupLabel
    /// Subtitle: 12.5pt, regular weight (400)
    case subtitle
    /// Pill: 12.5pt, weight 550
    case pill
    /// Footnote: 12pt, regular weight (400)
    case footnote
    /// Caption: 11pt, regular weight (400)
    case caption
    /// Button: 14.5pt, weight 550
    case button
    /// Icon medium: 20pt, regular weight (for SF Symbols)
    case iconMedium

    /// Returns a SwiftUI Font configured for this token.
    public var font: Font {
        let spec = Self.spec(self)
        return Font.custom(
            "Roboto Flex",
            size: spec.size,
            relativeTo: textStyle
        )
        .weight(approximateWeight)
    }

    // MARK: - Internal Specifications

    /// Test-only: returns the declared size and weight for this token.
    static func spec(_ token: HearthFont) -> (size: CGFloat, weight: Double) {
        switch token {
        case .largeTitle:
            return (34, 450)
        case .heroLarge:
            return (52, 450)
        case .iconHero:
            return (48, 450)
        case .title3:
            return (24, 450)
        case .pageTitle:
            return (22, 450)
        case .cardHeading:
            return (19, 450)
        case .rowTitle:
            return (15, 400)
        case .callout:
            return (14, 400)
        case .groupLabel:
            return (13, 550)
        case .subtitle:
            return (12.5, 400)
        case .pill:
            return (12.5, 550)
        case .footnote:
            return (12, 400)
        case .caption:
            return (11, 400)
        case .button:
            return (14.5, 550)
        case .iconMedium:
            return (20, 400)
        }
    }

    /// Maps each token to the nearest Dynamic Type text style for scaling.
    private var textStyle: Font.TextStyle {
        switch self {
        case .largeTitle:
            return .largeTitle
        case .heroLarge:
            return .largeTitle
        case .iconHero:
            return .largeTitle
        case .title3:
            return .title3
        case .pageTitle:
            return .title2
        case .cardHeading:
            return .title3
        case .rowTitle:
            return .body
        case .callout:
            return .callout
        case .groupLabel:
            return .subheadline
        case .subtitle:
            return .footnote
        case .pill:
            return .caption
        case .footnote:
            return .footnote
        case .caption:
            return .caption
        case .button:
            return .callout
        case .iconMedium:
            return .body
        }
    }

    /// Approximates custom variable weights with standard SwiftUI Font.Weight.
    /// 450 → .regular, 550 → .medium
    /// Note: Exact variable font weight control via CTFontDescriptor variation axis
    /// is deferred to polish phase for cross-platform compatibility.
    private var approximateWeight: Font.Weight {
        let spec = Self.spec(self)
        if spec.weight <= 425 {
            return .regular
        } else if spec.weight <= 500 {
            // 450 approximates to regular (or slightly heavier)
            return .regular
        } else {
            // 550 approximates to medium
            return .medium
        }
    }
}
