import Foundation

/// Everything a non-Beacon card (Lights, Quick actions, Favourites, Activity, Batteries)
/// needs to draw a style. Ported from Android's `cardLook` in `CardLook.kt`.
///
/// On iOS the Status style is each widget's existing state card, with that card's own inks: when
/// `statusColours` is true the view keeps what it draws today, and `surface` is nil. The inks here
/// apply to a chosen background (a colour or black).
public struct CardLook: Sendable, Equatable {
    /// The chosen background; nil: the card's own state colours.
    public let surface: CardSurface?
    public let ink: UInt32
    public let soft: UInt32
    public let faint: UInt32
    /// What needs you.
    public let flag: UInt32
    public let headline: UInt32
    /// The status strip on the leading edge; nil: none.
    public let strip: UInt32?
    /// A key's fill on a chosen background (the centre stop of `jewel_key.xml` / `jewel_key_dark.xml`).
    public let key: UInt32
    public let textScale: CGFloat
    public let smallPrint: Bool
    public let light: Bool
    /// Showing the card's own state colour (the Status style, or an emergency).
    public let statusColours: Bool

    /// The strip's size and inset, in points (`CardFrame` in `CardChrome.kt`).
    public static let stripWidth: CGFloat = 4
    public static let stripInset: CGFloat = 16
    public static let stripRadius: CGFloat = 2
}

private enum CardInk {
    static let white: UInt32 = 0xFFFFFFFF
    static let softWhite: UInt32 = 0xC7FFFFFF
    static let faintWhite: UInt32 = 0x99FFFFFF
    static let dark: UInt32 = 0xFF1B1D22
    static let softDark: UInt32 = 0xA61B1D22
    static let faintDark: UInt32 = 0x8C1B1D22
    static let accentOnDark: UInt32 = 0xFFFFC861
    static let accentOnLight: UInt32 = 0xFF9A5B00
    static let flagOnDark: UInt32 = 0xFFFFD27A
    static let keyOnDark: UInt32 = 0x26FFFFFF
    static let keyOnLight: UInt32 = 0x141B1D22
}

/// The look for `style` on a card: `warn` when it needs you (an accent on the user's background),
/// `emergency` when it is urgent (the card's own alert colours, whatever the style).
public func cardLook(_ style: CardStyle, warn: Bool, emergency: Bool) -> CardLook {
    let background = emergency ? CardBackground.status : style.background
    let surface: CardSurface? = switch background {
    case .status: nil
    case .colour(let colour): .colour(colour)
    case .black: CardSurface(fill: .solid(CardSurface.blackARGB))
    }
    let light = if case .colour(let colour) = background { colour.isLight } else { false }
    let accent = warn && !emergency && background != .status
    let ink = light ? CardInk.dark : CardInk.white
    let accentInk = light ? CardInk.accentOnLight : CardInk.accentOnDark
    return CardLook(
        surface: surface,
        ink: ink,
        soft: light ? CardInk.softDark : CardInk.softWhite,
        faint: light ? CardInk.faintDark : CardInk.faintWhite,
        flag: light ? CardInk.accentOnLight : accent ? accentInk : CardInk.flagOnDark,
        headline: accent ? accentInk : ink,
        strip: accent ? accentInk : nil,
        key: light ? CardInk.keyOnLight : CardInk.keyOnDark,
        textScale: style.textSize.scale,
        smallPrint: style.smallPrint,
        light: light,
        statusColours: background == .status)
}

/// What the widget container shows behind a non-Beacon card: the chosen background's first colour,
/// else the card's own `statusARGB`.
public func cardContainerARGB(_ style: CardStyle, statusARGB: UInt32) -> UInt32 {
    cardLook(style, warn: false, emergency: false).surface?.baseARGB ?? statusARGB
}
