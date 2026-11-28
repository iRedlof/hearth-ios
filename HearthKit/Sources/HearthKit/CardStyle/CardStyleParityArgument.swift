import Foundation

/// Parses the DEBUG launch argument `-parityCardStyle <value>`, so a parity fixture can be drawn in
/// any style without a real account.
///
///     <background>[;text=<smaller|normal|larger>][;small=<on|off>]
///
/// `<background>` is `status`, `black`, or `colour:<ocean|night|plum|rose|forest|slate|graphite|snow>`
/// (`color:` is accepted too). Options may be separated by `;` or `,` and are case-insensitive.
/// Anything unrecognised returns nil rather than a guess.
public func parityCardStyle(_ argument: String) -> CardStyle? {
    let parts = argument.lowercased()
        .split(whereSeparator: { $0 == ";" || $0 == "," })
        .map { $0.trimmingCharacters(in: .whitespaces) }
    guard let first = parts.first, let background = parityBackground(first) else { return nil }
    let start: CardStyle? = CardStyle.default.with(background: background)
    return parts.dropFirst().reduce(start) { style, option in
        style.flatMap { parityOption(option, on: $0) }
    }
}

private func parityBackground(_ text: String) -> CardBackground? {
    switch text {
    case "status": return .status
    case "black": return .black
    default:
        let pieces = text.split(separator: ":", maxSplits: 1).map(String.init)
        guard pieces.count == 2, ["colour", "color"].contains(pieces[0]),
              let colour = CardColour(rawValue: pieces[1]) else { return nil }
        return .colour(colour)
    }
}

private func parityOption(_ option: String, on style: CardStyle) -> CardStyle? {
    let pieces = option.split(separator: "=", maxSplits: 1).map(String.init)
    guard pieces.count == 2 else { return nil }
    switch pieces[0] {
    case "text":
        return CardTextSize(rawValue: pieces[1]).map(style.with(textSize:))
    case "small":
        switch pieces[1] {
        case "on": return style.with(smallPrint: true)
        case "off": return style.with(smallPrint: false)
        default: return nil
        }
    default:
        return nil
    }
}
