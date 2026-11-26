import Testing
import SwiftUI
@testable import HearthKit

@Suite("HearthFont Ramp Tests")
struct HearthFontRampTests {

    @Test("Type ramp sizes match spec")
    func rampSizesMatchSpec() {
        let specs: [(token: HearthFont, expectedSize: CGFloat, expectedWeight: Double)] = [
            (.largeTitle, 34, 450),
            (.cardHeading, 19, 450),
            (.pageTitle, 22, 450),
            (.rowTitle, 15, 400),
            (.groupLabel, 13, 550),
            (.subtitle, 12.5, 400),
            (.button, 14.5, 550),
            (.pill, 12.5, 550)
        ]

        for (token, expectedSize, expectedWeight) in specs {
            let spec = HearthFont.spec(token)
            #expect(spec.size == expectedSize, "Token \(token) size should be \(expectedSize), got \(spec.size)")
            #expect(spec.weight == expectedWeight, "Token \(token) weight should be \(expectedWeight), got \(spec.weight)")
        }
    }
}
