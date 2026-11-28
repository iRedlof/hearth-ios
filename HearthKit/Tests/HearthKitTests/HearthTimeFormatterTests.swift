import Testing
import Foundation
@testable import HearthKit

@Suite("HearthTimeFormatter")
struct HearthTimeFormatterTests {
    private let us = Locale(identifier: "en_US@hours=h12")
    private let gb = Locale(identifier: "en_GB@hours=h23")

    private func date(hour: Int, minute: Int = 0, day: Int = 27) throws -> Date {
        try #require(Calendar.current.date(from: DateComponents(
            year: 2026, month: 11, day: day, hour: hour, minute: minute
        )))
    }

    @Test("Short time has an ordinary space before AM/PM")
    func shortTime12Hour() throws {
        #expect(HearthTimeFormatter.shortTime(try date(hour: 22, minute: 30), locale: us) == "10:30 PM")
        #expect(HearthTimeFormatter.shortTime(try date(hour: 9, minute: 41), locale: us) == "9:41 AM")
    }

    @Test("Short time in a 24-hour locale has no AM/PM")
    func shortTime24Hour() throws {
        #expect(HearthTimeFormatter.shortTime(try date(hour: 22, minute: 30), locale: gb) == "22:30")
    }

    @Test("Hour only")
    func hourOnly() throws {
        #expect(HearthTimeFormatter.hourOnly(try date(hour: 22), locale: us) == "10 PM")
        #expect(HearthTimeFormatter.hourOnly(try date(hour: 6), locale: us) == "6 AM")
        #expect(HearthTimeFormatter.hourOnly(try date(hour: 22), locale: gb) == "22")
    }

    @Test("Hour range")
    func hourRange() throws {
        let start = try date(hour: 22), end = try date(hour: 6, day: 28)
        #expect(HearthTimeFormatter.hourRange(from: start, to: end, locale: us) == "10 PM–6 AM")
        let range24 = HearthTimeFormatter.hourRange(from: start, to: end, locale: gb)
        #expect(range24.hasPrefix("22–"))
        #expect(!range24.contains("AM") && !range24.contains("PM"))
    }

    @Test("Date with time has no seconds and an ordinary space")
    func dateWithTime() throws {
        let text = HearthTimeFormatter.dateWithTime(try date(hour: 15, minute: 37), locale: us)
        #expect(text.contains("Nov 27, 2026"))
        #expect(text.hasSuffix("3:37 PM"))
        let text24 = HearthTimeFormatter.dateWithTime(try date(hour: 15, minute: 37), locale: gb)
        #expect(text24.hasSuffix("15:37"))
    }

    @Test("Weekday with time")
    func weekdayTime() throws {
        let friday = try date(hour: 21, minute: 42)
        #expect(HearthTimeFormatter.weekdayTime(friday, locale: us) == "Fri 9:42 PM")
        #expect(HearthTimeFormatter.weekdayTime(friday, locale: gb) == "Fri 21:42")
    }

    @Test("Date with seconds keeps the seconds and an ordinary space")
    func dateWithSeconds() throws {
        let moment = try date(hour: 15, minute: 37).addingTimeInterval(5)
        #expect(HearthTimeFormatter.dateWithSeconds(moment, locale: us) == "Nov 27, 2026 at 3:37:05 PM")
        #expect(HearthTimeFormatter.dateWithSeconds(moment, locale: gb).hasSuffix("15:37:05"))
    }

    @Test("The time zone decides the hour that is shown")
    func timeZoneIsHonoured() throws {
        let utc = try #require(TimeZone(identifier: "UTC"))
        let tokyo = try #require(TimeZone(identifier: "Asia/Tokyo"))
        let noonUTC = Date(timeIntervalSince1970: 1_795_780_800)  // 2026-11-27 12:00:00 UTC
        #expect(HearthTimeFormatter.shortTime(noonUTC, locale: us, timeZone: utc) == "12:00 PM")
        #expect(HearthTimeFormatter.shortTime(noonUTC, locale: us, timeZone: tokyo) == "9:00 PM")
        #expect(HearthTimeFormatter.hourOnly(noonUTC, locale: us, timeZone: tokyo) == "9 PM")
        #expect(HearthTimeFormatter.weekdayTime(noonUTC, locale: us, timeZone: tokyo) == "Fri 9:00 PM")
        #expect(HearthTimeFormatter.dateWithTime(noonUTC, locale: us, timeZone: tokyo) == "Nov 27, 2026 at 9:00 PM")
    }

    @Test("No result contains a no-break space, which the app typeface cannot draw",
          arguments: ["en_US@hours=h12", "en_US_POSIX", "en_GB@hours=h23", "de_DE", "fr_FR", "ja_JP"])
    func noNoBreakSpaces(identifier: String) throws {
        let locale = Locale(identifier: identifier)
        let sample = try date(hour: 22, minute: 30)
        for text in [
            HearthTimeFormatter.shortTime(sample, locale: locale),
            HearthTimeFormatter.hourOnly(sample, locale: locale),
            HearthTimeFormatter.hourRange(from: sample, to: sample, locale: locale),
            HearthTimeFormatter.weekdayTime(sample, locale: locale),
            HearthTimeFormatter.dateWithTime(sample, locale: locale),
            HearthTimeFormatter.dateWithSeconds(sample, locale: locale),
        ] {
            #expect(!text.contains("\u{202F}"), "\(identifier): \(text)")
            #expect(!text.contains("\u{00A0}"), "\(identifier): \(text)")
        }
    }
}

@Suite("Times the kit writes for the screen")
struct KitTimeTextTests {
    private let us = Locale(identifier: "en_US")
    private let zone = TimeZone(secondsFromGMT: 0) ?? .current
    /// 2026-11-27 12:00:00 UTC, a Friday.
    private let noon = Date(timeIntervalSince1970: 1_795_780_800)
    private let hour: TimeInterval = 3600
    private let day: TimeInterval = 86_400

    private var texts: [String?] {
        [
            sinceLabel(noon.addingTimeInterval(-hour), now: noon, zone: zone, locale: us),
            sinceLabel(noon.addingTimeInterval(-2 * day), now: noon, zone: zone, locale: us),
            sinceLabel(noon.addingTimeInterval(-hour), noon, zone, us),
            sinceLabel(noon.addingTimeInterval(-2 * day), noon, zone, us),
            beaconCarEta(noon.addingTimeInterval(hour), noon, zone, us),
            beaconCarEta(noon.addingTimeInterval(day), noon, zone, us),
            activityTimeLabel(noon.addingTimeInterval(-hour), now: noon, zone: zone, locale: us),
            activityTimeLabel(noon.addingTimeInterval(-day), now: noon, zone: zone, locale: us),
            activityTimeLabel(noon.addingTimeInterval(-3 * day), now: noon, zone: zone, locale: us),
            thermostatObservationText(noon, locale: us, zone: zone),
            cpClockString(noon),
            widgetClock(noon),
        ]
    }

    @Test("None of them contains a no-break space")
    func noNoBreakSpaces() {
        for text in texts.compactMap({ $0 }) {
            #expect(!text.contains("\u{202F}"), "\(text)")
            #expect(!text.contains("\u{00A0}"), "\(text)")
        }
        #expect(texts.allSatisfy { $0 != nil })
    }

    @Test("They read as before: an ordinary space before AM/PM")
    func wording() {
        #expect(sinceLabel(noon.addingTimeInterval(-hour), now: noon, zone: zone, locale: us) == "since 11:00 AM")
        #expect(sinceLabel(noon.addingTimeInterval(-2 * day), now: noon, zone: zone, locale: us) == "since Wed 12:00 PM")
        #expect(sinceLabel(noon.addingTimeInterval(-9 * day), now: noon, zone: zone, locale: us) == "since Nov 18")
        #expect(beaconCarEta(noon.addingTimeInterval(day), noon, zone, us) == "Full by Sat 12:00 PM")
        #expect(activityTimeLabel(noon.addingTimeInterval(-day), now: noon, zone: zone, locale: us) == "Yest 12:00 PM")
        #expect(activityTimeLabel(noon.addingTimeInterval(-3 * day), now: noon, zone: zone, locale: us) == "Nov 24 12:00 PM")
        #expect(thermostatObservationText(noon, locale: us, zone: zone) == "Nov 27, 2026 at 12:00 PM")
    }
}
