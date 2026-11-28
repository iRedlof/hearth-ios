import Foundation

/// The one place user-visible times are formatted. Locale-aware, built on the thread-safe
/// `Date.FormatStyle` (never `DateFormatter`).
///
/// `Date.FormatStyle` separates the time from AM/PM with U+202F (narrow no-break space). The app's
/// typeface, Roboto Flex, has no glyph for it, so "10:30 PM" rendered as "10:30PM". Every result
/// is therefore normalised to an ordinary space.
public enum HearthTimeFormatter {
    /// "10:30 PM", or "22:30" in 24-hour locales.
    public static func shortTime(_ date: Date, locale: Locale = .current,
                                 timeZone: TimeZone = .current) -> String {
        normalised(date.formatted(style(locale, timeZone).hour().minute()))
    }

    /// "10 PM", or "22" in 24-hour locales.
    public static func hourOnly(_ date: Date, locale: Locale = .current,
                                timeZone: TimeZone = .current) -> String {
        normalised(date.formatted(style(locale, timeZone).hour()))
    }

    /// "10 PM–6 AM", or "22–06" style in 24-hour locales.
    public static func hourRange(from start: Date, to end: Date, locale: Locale = .current,
                                 timeZone: TimeZone = .current) -> String {
        "\(hourOnly(start, locale: locale, timeZone: timeZone))–\(hourOnly(end, locale: locale, timeZone: timeZone))"
    }

    /// "Mon 9:42 PM": the short weekday, then the short time.
    public static func weekdayTime(_ date: Date, locale: Locale = .current,
                                   timeZone: TimeZone = .current) -> String {
        let weekday = normalised(date.formatted(style(locale, timeZone).weekday(.abbreviated)))
        return "\(weekday) \(shortTime(date, locale: locale, timeZone: timeZone))"
    }

    /// "Nov 27, 2026 at 3:37 PM". Never includes seconds.
    public static func dateWithTime(_ date: Date, locale: Locale = .current,
                                    timeZone: TimeZone = .current) -> String {
        normalised(date.formatted(
            style(locale, timeZone).year().month(.abbreviated).day().hour().minute()
        ))
    }

    /// "Nov 27, 2026 at 3:37:05 PM", for readings whose exact second is the point.
    public static func dateWithSeconds(_ date: Date, locale: Locale = .current,
                                       timeZone: TimeZone = .current) -> String {
        normalised(date.formatted(
            style(locale, timeZone).year().month(.abbreviated).day().hour().minute().second()
        ))
    }

    /// Replaces the no-break spaces `Date.FormatStyle` emits with ordinary spaces.
    static func normalised(_ text: String) -> String {
        text.replacingOccurrences(of: "\u{202F}", with: " ")
            .replacingOccurrences(of: "\u{00A0}", with: " ")
    }

    private static func style(_ locale: Locale, _ timeZone: TimeZone) -> Date.FormatStyle {
        Date.FormatStyle(locale: locale, timeZone: timeZone)
    }
}
