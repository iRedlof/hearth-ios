import Foundation

/// The card colours, in Android's order (`CARD_COLOURS` / `CARD_COLOUR_NAMES` in `CardStyle.kt`).
/// Each is a vertical two-stop gradient; Snow, the last, is the only light one.
public enum CardColour: String, CaseIterable, Sendable, Codable {
    case ocean
    case night
    case plum
    case rose
    case forest
    case slate
    case graphite
    case snow

    /// The name shown under its swatch and in the summary.
    public var label: String { rawValue.capitalized }

    /// Top of the gradient (ARGB).
    public var topARGB: UInt32 { stops.top }

    /// Bottom of the gradient (ARGB).
    public var bottomARGB: UInt32 { stops.bottom }

    /// A light card takes dark inks.
    public var isLight: Bool { self == .snow }

    private var stops: (top: UInt32, bottom: UInt32) {
        switch self {
        case .ocean: (0xFF1D8FB4, 0xFF0A3C58)
        case .night: (0xFF2B3A67, 0xFF121A33)
        case .plum: (0xFF5B4B8A, 0xFF2A1F4A)
        case .rose: (0xFFB4536E, 0xFF5A1E33)
        case .forest: (0xFF4F7A3A, 0xFF1F3519)
        case .slate: (0xFF5A6474, 0xFF262B33)
        case .graphite: (0xFF3A3C42, 0xFF18191C)
        case .snow: (0xFFF4F5F7, 0xFFD9DDE3)
        }
    }
}

/// What a card's background is. Android also has Glass and Wallpaper; an iPhone widget cannot draw
/// either, so they are left out (owner decision 2026-11-27, see docs/CARD-STYLE-IOS.md).
public enum CardBackground: Sendable, Equatable {
    /// The widget's own state colours.
    case status
    case colour(CardColour)
    case black

    /// The name the summary uses (`CardBackground.label()` in `CardStylePage.kt`).
    public var label: String {
        switch self {
        case .status: "Status colours"
        case .colour(let colour): colour.label
        case .black: "Black"
        }
    }
}

extension CardBackground: Codable {
    /// `byState` is what the first iOS port stored for today's `status`.
    private enum CodingKeys: String, CodingKey { case status, byState, colour, black }
    private enum ColourKeys: String, CodingKey { case value = "_0" }

    /// Lenient like Android's `fromJson`: anything unrecognised is Status.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if container.contains(.black) {
            self = .black
        } else if container.contains(.colour) {
            let nested = try container.nestedContainer(keyedBy: ColourKeys.self, forKey: .colour)
            let name = try nested.decodeIfPresent(String.self, forKey: .value)
            self = name.flatMap(CardColour.init(rawValue:)).map(CardBackground.colour) ?? .status
        } else {
            self = .status
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .status:
            _ = container.nestedContainer(keyedBy: ColourKeys.self, forKey: .status)
        case .black:
            _ = container.nestedContainer(keyedBy: ColourKeys.self, forKey: .black)
        case .colour(let colour):
            var nested = container.nestedContainer(keyedBy: ColourKeys.self, forKey: .colour)
            try nested.encode(colour.rawValue, forKey: .value)
        }
    }
}

/// Text size, on top of the phone's own font size (`CardText` in `CardStyle.kt`).
public enum CardTextSize: String, CaseIterable, Sendable, Codable {
    case smaller
    case normal
    case larger

    /// What every text in the card is multiplied by.
    public var scale: CGFloat {
        switch self {
        case .smaller: 0.9
        case .normal: 1.0
        case .larger: 1.12
        }
    }

    public var label: String { rawValue.capitalized }
}

/// How a card looks: chosen for all cards or for one, in Card style.
public struct CardStyle: Sendable, Equatable {
    public let background: CardBackground
    public let textSize: CardTextSize
    /// "Checked 9:41 AM" and the other small print.
    public let smallPrint: Bool

    /// Every card's look until you choose. Android starts on Glass; iOS cannot draw it, so Status.
    public static let `default` = CardStyle(background: .status, textSize: .normal, smallPrint: true)

    public init(background: CardBackground, textSize: CardTextSize, smallPrint: Bool) {
        self.background = background
        self.textSize = textSize
        self.smallPrint = smallPrint
    }

    public func with(background: CardBackground) -> CardStyle {
        CardStyle(background: background, textSize: textSize, smallPrint: smallPrint)
    }

    public func with(textSize: CardTextSize) -> CardStyle {
        CardStyle(background: background, textSize: textSize, smallPrint: smallPrint)
    }

    public func with(smallPrint: Bool) -> CardStyle {
        CardStyle(background: background, textSize: textSize, smallPrint: smallPrint)
    }

    /// "Plum · Larger": the style in a few words, for the settings rows (`CardStyle.summary()`).
    public var summary: String {
        let parts: [String?] = [
            background.label,
            textSize == .normal ? nil : textSize.label,
            smallPrint ? nil : "no small print"
        ]
        return parts.compactMap { $0 }.joined(separator: " · ")
    }
}

extension CardStyle: Codable {
    private enum CodingKeys: String, CodingKey { case background, textSize, smallPrint }

    /// Each field falls back on its default alone, so one unreadable value never resets the rest.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let fallback = CardStyle.default
        let text = try container.decodeIfPresent(String.self, forKey: .textSize)
        self.init(
            background: try container.decodeIfPresent(CardBackground.self, forKey: .background) ?? fallback.background,
            textSize: text.flatMap(CardTextSize.init(rawValue:)) ?? fallback.textSize,
            smallPrint: try container.decodeIfPresent(Bool.self, forKey: .smallPrint) ?? fallback.smallPrint)
    }
}

/// The style a card draws with: its own when it has one, else All cards' (`effectiveStyle`).
public func resolveStyle(global: CardStyle, override: CardStyle?) -> CardStyle {
    override ?? global
}
