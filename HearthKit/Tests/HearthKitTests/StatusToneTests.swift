import Testing
import SwiftUI
@testable import HearthKit

@Suite("StatusTone Tests")
struct StatusToneTests {

    @Test("ok tone maps to green colors")
    func okToneMapsToGreen() {
        let tone = StatusTone.ok
        #expect(tone.bgARGB(.light) == HearthColor.greenBgLight)
        #expect(tone.bgARGB(.dark) == HearthColor.greenBgDark)
        #expect(tone.inkARGB(.light) == HearthColor.greenLight)
        #expect(tone.inkARGB(.dark) == HearthColor.greenDark)
    }

    @Test("warn tone maps to amber colors")
    func warnToneMapsToAmber() {
        let tone = StatusTone.warn
        #expect(tone.bgARGB(.light) == HearthColor.amberBgLight)
        #expect(tone.bgARGB(.dark) == HearthColor.amberBgDark)
        #expect(tone.inkARGB(.light) == HearthColor.amberLight)
        #expect(tone.inkARGB(.dark) == HearthColor.amberDark)
    }

    @Test("neutral tone maps to tint and mute colors")
    func neutralToneMapsToTintAndMute() {
        let tone = StatusTone.neutral
        #expect(tone.bgARGB(.light) == HearthColor.tintLight)
        #expect(tone.bgARGB(.dark) == HearthColor.tintDark)
        #expect(tone.inkARGB(.light) == HearthColor.muteLight)
        #expect(tone.inkARGB(.dark) == HearthColor.muteDark)
    }
}
