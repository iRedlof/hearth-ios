import Testing
import SwiftUI
@testable import HearthKit

@Suite("HearthFont Ramp Tests")
struct HearthFontRampTests {

    @Test("Type ramp sizes match spec")
    func rampSizesMatchSpec() {
        let specs: [(token: HearthFont, expectedSize: CGFloat, expectedWeight: Double)] = [
            (.largeTitle, 34, 450),
            (.heroLarge, 52, 450),
            (.iconHero, 48, 450),
            (.title3, 24, 450),
            (.iconLarge, 24, 400),
            (.pageTitle, 22, 450),
            (.cardHeading, 19, 450),
            (.rowTitle, 15, 400),
            (.callout, 14, 400),
            (.iconSmall, 14, 400),
            (.groupLabel, 13, 550),
            (.subtitle, 12.5, 400),
            (.pill, 12.5, 550),
            (.footnote, 12, 400),
            (.caption, 11, 400),
            (.button, 14.5, 550),
            (.iconMedium, 20, 400)
        ]

        for (token, expectedSize, expectedWeight) in specs {
            let spec = HearthFont.spec(token)
            #expect(spec.size == expectedSize, "Token \(token) size should be \(expectedSize), got \(spec.size)")
            #expect(spec.weight == expectedWeight, "Token \(token) weight should be \(expectedWeight), got \(spec.weight)")
        }
    }
}
