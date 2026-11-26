import Testing
import SwiftUI
@testable import HearthKit

@Suite("HearthSwitch Tests")
struct HearthSwitchTests {
    @Test("Switch geometry from metrics")
    func switchGeometryFromMetrics() {
        #expect(HearthSwitch.Geometry.trackWidth == 46)
        #expect(HearthSwitch.Geometry.trackHeight == 28)
        #expect(HearthSwitch.Geometry.thumb == 20)
    }

    @Test("Track colors light mode")
    func trackColorsLight() {
        // Track ON (light) = HearthColor.inkLight
        #expect(HearthSwitch.TestColors.trackOnLight == HearthColor.inkLight)
        // Track OFF (light) = 0xFFD9D4CD
        #expect(HearthSwitch.TestColors.trackOffLight == 0xFFD9D4CD)
    }

    @Test("Track colors dark mode")
    func trackColorsDark() {
        // Track ON (dark) = HearthColor.inkDark
        #expect(HearthSwitch.TestColors.trackOnDark == HearthColor.inkDark)
        // Track OFF (dark) = 0xFF3A3835
        #expect(HearthSwitch.TestColors.trackOffDark == 0xFF3A3835)
    }

    @Test("Thumb colors light mode")
    func thumbColorsLight() {
        // Thumb ON (light) = HearthColor.onAccentLight
        #expect(HearthSwitch.TestColors.thumbOnLight == HearthColor.onAccentLight)
        // Thumb OFF (light) = 0xFFFFFFFF
        #expect(HearthSwitch.TestColors.thumbOffLight == 0xFFFFFFFF)
    }

    @Test("Thumb colors dark mode")
    func thumbColorsDark() {
        // Thumb ON (dark) = HearthColor.onAccentDark
        #expect(HearthSwitch.TestColors.thumbOnDark == HearthColor.onAccentDark)
        // Thumb OFF (dark) = 0xFF8E8981
        #expect(HearthSwitch.TestColors.thumbOffDark == 0xFF8E8981)
    }
}
