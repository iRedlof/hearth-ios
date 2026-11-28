import Testing
import Foundation
@testable import HearthKit

@Suite("CardStyle Model")
struct CardStyleTests {
    @Test("Default is Status, normal text, small print on (Glass is not available on iOS)")
    func defaultValues() {
        #expect(CardStyle.default.background == .status)
        #expect(CardStyle.default.textSize == .normal)
        #expect(CardStyle.default.smallPrint)
    }

    @Test("Text sizes scale 0.9 / 1.0 / 1.12, as on Android")
    func textSizeScales() {
        #expect(CardTextSize.smaller.scale == 0.9)
        #expect(CardTextSize.normal.scale == 1.0)
        #expect(CardTextSize.larger.scale == 1.12)
        #expect(CardTextSize.allCases.map(\.label) == ["Smaller", "Normal", "Larger"])
    }

    @Test("The eight colours keep Android's order, names and gradient stops")
    func colourStops() {
        let expected: [(CardColour, String, UInt32, UInt32)] = [
            (.ocean, "Ocean", 0xFF1D8FB4, 0xFF0A3C58), (.night, "Night", 0xFF2B3A67, 0xFF121A33),
            (.plum, "Plum", 0xFF5B4B8A, 0xFF2A1F4A), (.rose, "Rose", 0xFFB4536E, 0xFF5A1E33),
            (.forest, "Forest", 0xFF4F7A3A, 0xFF1F3519), (.slate, "Slate", 0xFF5A6474, 0xFF262B33),
            (.graphite, "Graphite", 0xFF3A3C42, 0xFF18191C), (.snow, "Snow", 0xFFF4F5F7, 0xFFD9DDE3)
        ]
        #expect(CardColour.allCases == expected.map(\.0))
        for (colour, name, top, bottom) in expected {
            #expect(colour.label == name)
            #expect(colour.topARGB == top)
            #expect(colour.bottomARGB == bottom)
        }
        #expect(CardColour.allCases.filter(\.isLight) == [.snow])
    }

    @Test("resolveStyle prefers the card's own style")
    func resolveStylePrefersOwn() {
        let global = CardStyle(background: .black, textSize: .smaller, smallPrint: false)
        let own = CardStyle(background: .colour(.ocean), textSize: .larger, smallPrint: true)
        #expect(resolveStyle(global: global, override: own) == own)
        #expect(resolveStyle(global: global, override: nil) == global)
    }

    @Test("Copies change one axis and leave the original alone")
    func copies() {
        let base = CardStyle.default
        #expect(base.with(background: .black).background == .black)
        #expect(base.with(textSize: .larger).textSize == .larger)
        #expect(base.with(smallPrint: false).smallPrint == false)
        #expect(base == .default)
    }

    @Test("Every background round-trips through storage", arguments: [
        CardBackground.status, .black, .colour(.ocean), .colour(.snow)
    ])
    func codableRoundTrip(background: CardBackground) throws {
        let style = CardStyle(background: background, textSize: .larger, smallPrint: false)
        let decoded = try JSONDecoder().decode(CardStyle.self, from: JSONEncoder().encode(style))
        #expect(decoded == style)
    }

    @Test("Styles saved by the first iOS port still decode: byState becomes Status")
    func legacyByStateMigrates() throws {
        let legacy = #"{"background":{"byState":{}},"textSize":"larger","smallPrint":false}"#
        let decoded = try JSONDecoder().decode(CardStyle.self, from: Data(legacy.utf8))
        #expect(decoded == CardStyle(background: .status, textSize: .larger, smallPrint: false))
    }

    @Test("Legacy colour and black payloads keep their meaning")
    func legacyColourAndBlack() throws {
        let colour = #"{"background":{"colour":{"_0":"plum"}},"textSize":"normal","smallPrint":true}"#
        let black = #"{"background":{"black":{}},"textSize":"smaller","smallPrint":true}"#
        #expect(try JSONDecoder().decode(CardStyle.self, from: Data(colour.utf8)).background == .colour(.plum))
        #expect(try JSONDecoder().decode(CardStyle.self, from: Data(black.utf8))
            == CardStyle(background: .black, textSize: .smaller, smallPrint: true))
    }

    @Test("A legacy overrides dictionary decodes kind by kind")
    func legacyOverridesDictionary() throws {
        let legacy = #"{"alarm":{"background":{"byState":{}},"textSize":"normal","smallPrint":true},"#
            + #""car":{"background":{"colour":{"_0":"rose"}},"textSize":"larger","smallPrint":false}}"#
        let decoded = try JSONDecoder().decode([String: CardStyle].self, from: Data(legacy.utf8))
        #expect(decoded["alarm"] == .default)
        #expect(decoded["car"] == CardStyle(background: .colour(.rose), textSize: .larger, smallPrint: false))
    }

    @Test("A style saved for the removed Glance widget is dropped, the others are kept")
    func removedKindOverrideIsDropped() throws {
        let stored = #"{"glance":{"background":{"black":{}},"textSize":"larger","smallPrint":false},"#
            + #""car":{"background":{"colour":{"_0":"rose"}},"textSize":"larger","smallPrint":false}}"#
        let overrides = try cardStyleOverrides(fromStored: Data(stored.utf8))
        #expect(overrides == ["car": CardStyle(background: .colour(.rose), textSize: .larger, smallPrint: false)])
    }

    @Test("Stored own styles survive for every current widget kind", arguments: HomeWidgetKind.allCases)
    func currentKindOverrideIsKept(kind: HomeWidgetKind) throws {
        let style = CardStyle(background: .black, textSize: .smaller, smallPrint: false)
        let stored = try JSONEncoder().encode([kind.rawValue: style])
        #expect(try cardStyleOverrides(fromStored: stored) == [kind.rawValue: style])
    }

    @Test("Unreadable own styles are reported, not guessed")
    func unreadableOverridesThrow() {
        #expect(throws: (any Error).self) { try cardStyleOverrides(fromStored: Data("not json".utf8)) }
    }

    @Test("Unknown or missing fields fall back the way Android's fromJson does")
    func lenientDecoding() throws {
        let unknown = #"{"background":{"glass":{"_0":76}},"textSize":"huge"}"#
        #expect(try JSONDecoder().decode(CardStyle.self, from: Data(unknown.utf8)) == .default)
        let unknownColour = #"{"background":{"colour":{"_0":"teal"}},"textSize":"normal","smallPrint":false}"#
        #expect(try JSONDecoder().decode(CardStyle.self, from: Data(unknownColour.utf8))
            == CardStyle(background: .status, textSize: .normal, smallPrint: false))
    }

    @Test("Summary reads like Android's settings row")
    func summary() {
        #expect(CardStyle.default.summary == "Status colours")
        #expect(CardStyle(background: .colour(.plum), textSize: .larger, smallPrint: true).summary == "Plum · Larger")
        #expect(CardStyle(background: .black, textSize: .smaller, smallPrint: false).summary
            == "Black · Smaller · no small print")
        #expect(CardStyle(background: .colour(.snow), textSize: .normal, smallPrint: false).summary
            == "Snow · no small print")
    }
}

@Suite("CardStyle scope")
struct CardStyleScopeTests {
    @Test("Only the All-cards page opens editing the shared style")
    func opensOnJustThisCard() {
        #expect(cardStyleFollowsAll(forKind: nil))
        #expect(!cardStyleFollowsAll(forKind: .alarm))
    }

    @Test("The per-widget row says whose style the card uses")
    func entrySubtitle() {
        #expect(cardStyleEntrySubtitle(own: nil) == "Follows All cards")
        #expect(cardStyleEntrySubtitle(own: CardStyle(background: .colour(.plum), textSize: .larger, smallPrint: true))
            == "Its own: Plum · Larger")
    }

    @Test("Helper text names the card being styled")
    func scopeHelper() {
        #expect(cardStyleScopeHelper(follows: true, name: "Alarm")
            == "Changes below restyle all your cards. Pick \"Just this card\" to style Alarm on its own.")
        #expect(cardStyleScopeHelper(follows: false, name: "Alarm") == "Changes below restyle only Alarm.")
    }

    @Test("The All-cards page writes the shared style")
    func allCardsTarget() {
        #expect(cardStyleSaveTarget(kind: nil, follows: true) == .allCards)
    }

    @Test("A widget page on Just this card never writes the shared style")
    func ownTarget() {
        #expect(cardStyleSaveTarget(kind: .car, follows: false) == .own(.car))
        #expect(cardStyleSaveTarget(kind: .car, follows: true) == .allCards)
    }

    @Test("The stepper wraps around the added widgets")
    func stepperWraps() {
        #expect(cardStylePreviewIndex(0, step: -1, count: 3) == 2)
        #expect(cardStylePreviewIndex(2, step: 1, count: 3) == 0)
        #expect(cardStylePreviewIndex(1, step: 1, count: 3) == 2)
        #expect(cardStylePreviewIndex(5, step: 0, count: 3) == 2)
        #expect(cardStylePreviewIndex(0, step: 1, count: 0) == 0)
    }
}

@Suite("CardStyle parity argument")
struct CardStyleParityArgumentTests {
    @Test("Backgrounds parse", arguments: [
        ("status", CardBackground.status), ("black", .black), ("colour:plum", .colour(.plum)),
        ("colour:snow", .colour(.snow)), ("color:Ocean", .colour(.ocean)), (" Black ", .black)
    ])
    func backgrounds(argument: String, expected: CardBackground) {
        #expect(parityCardStyle(argument) == CardStyle.default.with(background: expected))
    }

    @Test("Text size and small print ride behind semicolons or commas")
    func options() {
        #expect(parityCardStyle("colour:plum;text=larger;small=off")
            == CardStyle(background: .colour(.plum), textSize: .larger, smallPrint: false))
        #expect(parityCardStyle("black,text=smaller,small=on")
            == CardStyle(background: .black, textSize: .smaller, smallPrint: true))
        #expect(parityCardStyle("status;small=off") == CardStyle.default.with(smallPrint: false))
    }

    @Test("Anything unrecognised is rejected rather than guessed", arguments: [
        "", "glass", "colour", "colour:teal", "black;text=huge", "black;small=maybe", "black;corners=square"
    ])
    func rejects(argument: String) {
        #expect(parityCardStyle(argument) == nil)
    }
}
