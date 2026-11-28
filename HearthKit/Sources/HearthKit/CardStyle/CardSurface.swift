import Foundation

/// What a surface is filled with (colours ARGB).
public enum CardFill: Sendable, Equatable {
    case solid(UInt32)
    /// Top to bottom (Android `angle="270"`).
    case vertical(top: UInt32, bottom: UInt32)
    /// Top-leading to bottom-trailing (Android `angle="315"`).
    case diagonal(start: UInt32, centre: UInt32, end: UInt32)

    /// The first colour: what the widget container shows before the card draws.
    public var baseARGB: UInt32 {
        switch self {
        case .solid(let argb): argb
        case .vertical(let top, _): top
        case .diagonal(let start, _, _): start
        }
    }
}

/// The light across the top of a colour card (the second layer of `jewel_card_c*.xml`).
public struct CardSheen: Sendable, Equatable {
    public let topARGB: UInt32
    public let centreARGB: UInt32
    public let bottomARGB: UInt32
    /// How far down the card it reaches, in points (Android `android:height="96dp"`).
    public let height: CGFloat

    public init(topARGB: UInt32, centreARGB: UInt32, bottomARGB: UInt32, height: CGFloat = CardSheen.standardHeight) {
        self.topARGB = topARGB
        self.centreARGB = centreARGB
        self.bottomARGB = bottomARGB
        self.height = height
    }

    public static let standardHeight: CGFloat = 96
    /// `jewel_card_c0…c6`.
    public static let dark = CardSheen(topARGB: 0x38FFFFFF, centreARGB: 0x12FFFFFF, bottomARGB: 0x00FFFFFF)
}

/// Everything a view needs to paint a styled background: the fill, then its lighting and edge.
public struct CardSurface: Sendable, Equatable {
    public let fill: CardFill
    public let sheen: CardSheen?
    /// A 1pt edge; nil: none.
    public let strokeARGB: UInt32?
    /// Directional lighting over a solid fill (`beacon_raised_body_glaze.xml`); nil: none.
    public let glaze: CardFill?

    public init(fill: CardFill, sheen: CardSheen? = nil, strokeARGB: UInt32? = nil, glaze: CardFill? = nil) {
        self.fill = fill
        self.sheen = sheen
        self.strokeARGB = strokeARGB
        self.glaze = glaze
    }

    public var baseARGB: UInt32 { fill.baseARGB }

    /// The width of `strokeARGB`, in points (Android `android:width="1dp"`).
    public static let strokeWidth: CGFloat = 1
    /// `jewel_card_c0…c6`'s edge.
    static let darkStrokeARGB: UInt32 = 0x1FFFFFFF
    static let blackARGB: UInt32 = 0xFF000000

    /// A dark colour's body: `jewel_card_c0…c6` (gradient, sheen, edge). Snow, the one light
    /// colour, has its own body (`beaconLook`).
    static func colour(_ colour: CardColour) -> CardSurface {
        CardSurface(fill: .vertical(top: colour.topARGB, bottom: colour.bottomARGB),
                    sheen: .dark, strokeARGB: darkStrokeARGB)
    }
}
