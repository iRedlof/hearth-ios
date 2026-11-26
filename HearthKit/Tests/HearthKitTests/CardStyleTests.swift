import Testing
import Foundation
import SwiftUI
@testable import HearthKit

@Suite("CardStyle Model")
struct CardStyleTests {
    @Test("resolveStyle returns override when present")
    func resolveStyleReturnsOverride() {
        let global = CardStyle(background: .byState, textSize: .normal, smallPrint: true)
        let override = CardStyle(background: .colour(.ocean), textSize: .larger, smallPrint: false)
        let result = resolveStyle(global: global, override: override)
        #expect(result == override)
    }

    @Test("resolveStyle returns global when no override")
    func resolveStyleReturnsGlobal() {
        let global = CardStyle(background: .black, textSize: .smaller, smallPrint: false)
        let result = resolveStyle(global: global, override: nil)
        #expect(result == global)
    }

    @Test("CardTextSize scale values are correct")
    func textSizeScales() {
        #expect(CardTextSize.smaller.scale == 0.9)
        #expect(CardTextSize.normal.scale == 1.0)
        #expect(CardTextSize.larger.scale == 1.12)
    }

    @Test("CardStyle Codable round-trip with byState")
    func codableByState() throws {
        let style = CardStyle(background: .byState, textSize: .normal, smallPrint: true)
        let encoded = try JSONEncoder().encode(style)
        let decoded = try JSONDecoder().decode(CardStyle.self, from: encoded)
        #expect(decoded == style)
    }

    @Test("CardStyle Codable round-trip with colour")
    func codableColour() throws {
        let style = CardStyle(background: .colour(.ocean), textSize: .larger, smallPrint: false)
        let encoded = try JSONEncoder().encode(style)
        let decoded = try JSONDecoder().decode(CardStyle.self, from: encoded)
        #expect(decoded == style)
    }

    @Test("CardStyle Codable round-trip with black")
    func codableBlack() throws {
        let style = CardStyle(background: .black, textSize: .smaller, smallPrint: true)
        let encoded = try JSONEncoder().encode(style)
        let decoded = try JSONDecoder().decode(CardStyle.self, from: encoded)
        #expect(decoded == style)
    }

    @Test("CardColour.fillARGB light differs from dark for ocean")
    func oceanLightDarkDiffer() {
        let light = CardColour.ocean.fillARGB(.light)
        let dark = CardColour.ocean.fillARGB(.dark)
        #expect(light != dark)
        #expect(light == 0xFF1D8FB4)
        #expect(dark == 0xFF0A3C58)
    }

    @Test("CardColour.fillARGB light differs from dark for plum")
    func plumLightDarkDiffer() {
        let light = CardColour.plum.fillARGB(.light)
        let dark = CardColour.plum.fillARGB(.dark)
        #expect(light != dark)
        #expect(light == 0xFF5B4B8A)
        #expect(dark == 0xFF2A1F4A)
    }

    @Test("CardStyle.default has expected values")
    func defaultValues() {
        let def = CardStyle.default
        #expect(def.background == .byState)
        #expect(def.textSize == .normal)
        #expect(def.smallPrint == true)
    }

    @Test("CardBackground equality works")
    func backgroundEquality() {
        #expect(CardBackground.byState == .byState)
        #expect(CardBackground.black == .black)
        #expect(CardBackground.colour(.ocean) == .colour(.ocean))
        #expect(CardBackground.colour(.ocean) != .colour(.night))
        #expect(CardBackground.byState != .black)
    }

    @Test("cardTextScale returns correct values")
    func textScaleHelper() {
        #expect(cardTextScale(.smaller) == 0.9)
        #expect(cardTextScale(.normal) == 1.0)
        #expect(cardTextScale(.larger) == 1.12)
    }

    @Test("cardContentFillARGB byState uses tone fill")
    func contentFillByState() {
        let toneFill: UInt32 = 0xFFB6D9C1  // mint tone
        let lightResult = cardContentFillARGB(.byState, tone: toneFill, .light)
        let darkResult = cardContentFillARGB(.byState, tone: toneFill, .dark)
        #expect(lightResult == toneFill)
        #expect(darkResult == toneFill)
    }

    @Test("cardContentFillARGB colour uses CardColour fill")
    func contentFillColour() {
        let toneFill: UInt32 = 0xFFB6D9C1  // ignored when colour is chosen
        let lightResult = cardContentFillARGB(.colour(.ocean), tone: toneFill, .light)
        let darkResult = cardContentFillARGB(.colour(.ocean), tone: toneFill, .dark)
        #expect(lightResult == CardColour.ocean.fillARGB(.light))
        #expect(darkResult == CardColour.ocean.fillARGB(.dark))
        #expect(lightResult != toneFill)  // doesn't use tone
    }

    @Test("cardContentFillARGB black uses near-black")
    func contentFillBlack() {
        let toneFill: UInt32 = 0xFFB6D9C1  // ignored when black is chosen
        let lightResult = cardContentFillARGB(.black, tone: toneFill, .light)
        let darkResult = cardContentFillARGB(.black, tone: toneFill, .dark)
        // Near-black values: lighter in light mode, darker in dark mode
        #expect(lightResult == 0xFF1A1A1A)
        #expect(darkResult == 0xFF0D0D0D)
        #expect(lightResult != toneFill)  // doesn't use tone
    }
}
