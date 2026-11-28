import Testing
import Foundation
@testable import HearthKit

private func style(_ background: CardBackground, _ text: CardTextSize = .normal, small: Bool = true) -> CardStyle {
    CardStyle(background: background, textSize: text, smallPrint: small)
}

@Suite("Beacon look (Alarm, Thermostat, Car, ChargePoint)")
struct BeaconLookTests {
    @Test("Status paints the body Android's raised graphite")
    func statusBody() {
        let look = beaconLook(style(.status))
        #expect(look.body == CardSurface(fill: .solid(0xFF262B27)))
        #expect(look.body.baseARGB == 0xFF262B27)
        #expect(!look.light)
        #expect(look.ink == 0xFFF2F5ED)
        #expect(look.soft == 0xFFB9C8BC)
        #expect(look.faint == 0xFF829587)
    }

    @Test("A colour paints the body its vertical gradient with the sheen and the stroke")
    func colourBody() {
        let look = beaconLook(style(.colour(.plum)))
        #expect(look.body.fill == .vertical(top: 0xFF5B4B8A, bottom: 0xFF2A1F4A))
        #expect(look.body.sheen == CardSheen(topARGB: 0x38FFFFFF, centreARGB: 0x12FFFFFF, bottomARGB: 0x00FFFFFF))
        #expect(look.body.sheen?.height == 96)
        #expect(look.body.strokeARGB == 0x1FFFFFFF)
        #expect(look.body.glaze == nil)
        #expect(look.body.baseARGB == 0xFF5B4B8A)
        #expect(!look.light)
        #expect(look.ink == 0xFFF2F5ED)
    }

    @Test("Every dark colour uses its own two stops", arguments: CardColour.allCases.filter { !$0.isLight })
    func everyDarkColour(colour: CardColour) {
        #expect(beaconLook(style(.colour(colour))).body.fill
            == .vertical(top: colour.topARGB, bottom: colour.bottomARGB))
    }

    @Test("Snow gives the light Beacon body with dark inks")
    func snowBody() {
        let look = beaconLook(style(.colour(.snow)))
        #expect(look.body == CardSurface(fill: .diagonal(start: 0xFFFEFCF4, centre: 0xFFF2F1E6, end: 0xFFDFE5D9)))
        #expect(look.light)
        #expect(look.ink == 0xFF26342C)
        #expect(look.soft == 0xFF56665B)
        #expect(look.faint == 0xFF79847A)
        #expect(look.chip == 0x14000000)
        #expect(look.chipFaint == 0x0D000000)
        #expect(look.chipPrimary == 0xFF2A2A2A)
        #expect(look.chipPrimaryInk == 0xFFF0F0F0)
        #expect(look.heat == 0xFF855016)
        #expect(look.cool == 0xFF316D85)
        #expect(look.secure == 0xFF2D633F)
        #expect(look.alert == 0xFFB3261E)
    }

    @Test("Black is pure black under Android's body glaze")
    func blackBody() {
        let look = beaconLook(style(.black))
        #expect(look.body.fill == .solid(0xFF000000))
        #expect(look.body.glaze == .diagonal(start: 0x14FFFFFF, centre: 0x00000000, end: 0x18000000))
        #expect(look.body.sheen == nil)
        #expect(look.body.strokeARGB == nil)
        #expect(look.body.baseARGB == 0xFF000000)
    }

    @Test("Dark bodies share the flat chip tokens")
    func darkChips() {
        for background in [CardBackground.status, .black, .colour(.ocean)] {
            let look = beaconLook(style(background))
            #expect(look.chip == 0x1AFFFFFF)
            #expect(look.chipFaint == 0x12FFFFFF)
            #expect(look.chipPrimary == 0xFFF0F0F0)
            #expect(look.chipPrimaryInk == 0xFF1C1C1A)
            #expect(look.heat == 0xFFF6D58A)
            #expect(look.cool == 0xFFA6D5FF)
            #expect(look.secure == 0xFF8FD6A8)
            #expect(look.alert == 0xFFF2A0A4)
        }
    }

    @Test("Text scale and small print come straight from the style")
    func scaleAndSmallPrint() {
        let look = beaconLook(style(.status, .larger, small: false))
        #expect(look.textScale == 1.12)
        #expect(!look.smallPrint)
        #expect(beaconLook(style(.status, .smaller)).textScale == 0.9)
    }

    @Test("The style never reaches the rail: the look carries no rail colour")
    func railKeepsState() {
        // The rail is drawn from the widget's own tone (BeaconTone / the ChargePoint orange); the
        // look only describes the body, so no style can recolour the rail.
        let tone = BeaconTone.mint
        for background in [CardBackground.status, .black, .colour(.rose), .colour(.snow)] {
            let look = beaconLook(style(background))
            #expect(look.body.baseARGB != tone.fillARGB)
        }
    }
}

@Suite("Card look (Doors, Lights, Quick actions, Favourites, Activity, Batteries)")
struct CardLookTests {
    @Test("Status keeps the card's own state colours")
    func status() {
        let look = cardLook(style(.status), warn: true, emergency: false)
        #expect(look.surface == nil)
        #expect(look.statusColours)
        #expect(look.strip == nil)
        #expect(!look.light)
    }

    @Test("A colour fills the card with its gradient, sheen and stroke, in white inks")
    func colour() {
        let look = cardLook(style(.colour(.ocean)), warn: false, emergency: false)
        #expect(look.surface == CardSurface(fill: .vertical(top: 0xFF1D8FB4, bottom: 0xFF0A3C58),
            sheen: CardSheen(topARGB: 0x38FFFFFF, centreARGB: 0x12FFFFFF, bottomARGB: 0x00FFFFFF),
            strokeARGB: 0x1FFFFFFF))
        #expect(!look.statusColours)
        #expect(look.ink == 0xFFFFFFFF)
        #expect(look.soft == 0xC7FFFFFF)
        #expect(look.faint == 0x99FFFFFF)
        #expect(look.flag == 0xFFFFD27A)
        #expect(look.headline == 0xFFFFFFFF)
        #expect(look.key == 0x26FFFFFF)
    }

    @Test("Snow is the light card: dark inks, brighter sheen, dark stroke")
    func snow() {
        let look = cardLook(style(.colour(.snow)), warn: false, emergency: false)
        #expect(look.surface == CardSurface(fill: .vertical(top: 0xFFF4F5F7, bottom: 0xFFD9DDE3),
            sheen: CardSheen(topARGB: 0x66FFFFFF, centreARGB: 0x12FFFFFF, bottomARGB: 0x00FFFFFF),
            strokeARGB: 0x1F000000))
        #expect(look.light)
        #expect(look.ink == 0xFF1B1D22)
        #expect(look.soft == 0xA61B1D22)
        #expect(look.faint == 0x8C1B1D22)
        #expect(look.flag == 0xFF9A5B00)
        #expect(look.key == 0x141B1D22)
    }

    @Test("Black is pure black with white inks")
    func black() {
        let look = cardLook(style(.black), warn: false, emergency: false)
        #expect(look.surface == CardSurface(fill: .solid(0xFF000000)))
        #expect(look.ink == 0xFFFFFFFF)
    }

    @Test("Needing you shows as an accent on the chosen background")
    func warnAccent() {
        let dark = cardLook(style(.black), warn: true, emergency: false)
        #expect(dark.headline == 0xFFFFC861)
        #expect(dark.strip == 0xFFFFC861)
        #expect(dark.flag == 0xFFFFC861)
        let light = cardLook(style(.colour(.snow)), warn: true, emergency: false)
        #expect(light.headline == 0xFF9A5B00)
        #expect(light.strip == 0xFF9A5B00)
    }

    @Test("An emergency keeps the card's own alert colours whatever the style")
    func emergency() {
        let look = cardLook(style(.colour(.snow)), warn: true, emergency: true)
        #expect(look.surface == nil)
        #expect(look.statusColours)
        #expect(look.strip == nil)
        #expect(!look.light)
    }

    @Test("The widget container follows the chosen background, else the card's own colour")
    func container() {
        let tone: UInt32 = 0xFFB6D9C1
        #expect(cardContainerARGB(style(.status), statusARGB: tone) == tone)
        #expect(cardContainerARGB(style(.black), statusARGB: tone) == 0xFF000000)
        #expect(cardContainerARGB(style(.colour(.rose)), statusARGB: tone) == 0xFFB4536E)
    }

    @Test("Text scale and small print come straight from the style")
    func scaleAndSmallPrint() {
        let look = cardLook(style(.black, .smaller, small: false), warn: false, emergency: false)
        #expect(look.textScale == 0.9)
        #expect(!look.smallPrint)
    }
}

@Suite("Small print")
struct CardSmallPrintTests {
    @Test("The Checked stamp hides with small print off, but Checking… always shows")
    func checkedStamp() {
        #expect(cardShowsCheckedStamp(smallPrint: true, checking: false))
        #expect(!cardShowsCheckedStamp(smallPrint: false, checking: false))
        #expect(cardShowsCheckedStamp(smallPrint: false, checking: true))
    }

    @Test("ChargePoint context lines are small print")
    func chargePointContext() {
        let lines = ["of 86 plugs", "7 in use"]
        #expect(cpContextLines(lines, smallPrint: true) == lines)
        #expect(cpContextLines(lines, smallPrint: false).isEmpty)
    }

    @Test("Activity drops who did it")
    func activityBy() {
        let at = Date(timeIntervalSince1970: 1_000)
        let items = [ActivityItem(at: at, kind: .lock, text: "Front door locked", by: "Goodnight", name: "Front door"),
                     ActivityItem(at: at, kind: .door, text: "Garage closed", by: nil)]
        #expect(activityItems(items, smallPrint: true) == items)
        let hidden = activityItems(items, smallPrint: false)
        #expect(hidden.map(\.by) == [nil, nil])
        #expect(hidden.map(\.text) == items.map(\.text))
        #expect(hidden.map(\.name) == items.map(\.name))
    }
}
