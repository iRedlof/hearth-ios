import Testing
import SwiftUI
@testable import HearthKit

@Suite("TileHue Tests")
struct TileHueTests {

    @Test("Blue hue ARGB values")
    func blueHueColors() {
        #expect(TileHue.blue.fillARGB(.light) == 0xFFDDEBFA)
        #expect(TileHue.blue.inkARGB(.light) == 0xFF1F4E79)
        #expect(TileHue.blue.fillARGB(.dark) == 0xFF1D3247)
        #expect(TileHue.blue.inkARGB(.dark) == 0xFF9CC6F0)
    }

    @Test("Orange hue ARGB values")
    func orangeHueColors() {
        #expect(TileHue.orange.fillARGB(.light) == 0xFFFCE3CF)
        #expect(TileHue.orange.inkARGB(.light) == 0xFF8A3A0A)
        #expect(TileHue.orange.fillARGB(.dark) == 0xFF43281A)
        #expect(TileHue.orange.inkARGB(.dark) == 0xFFF4B48A)
    }

    @Test("Purple hue ARGB values")
    func purpleHueColors() {
        #expect(TileHue.purple.fillARGB(.light) == 0xFFEAE3FB)
        #expect(TileHue.purple.inkARGB(.light) == 0xFF4B348F)
        #expect(TileHue.purple.fillARGB(.dark) == 0xFF2E2648)
        #expect(TileHue.purple.inkARGB(.dark) == 0xFFC4B3F5)
    }

    @Test("Green hue ARGB values")
    func greenHueColors() {
        #expect(TileHue.green.fillARGB(.light) == 0xFFDDF0E3)
        #expect(TileHue.green.inkARGB(.light) == 0xFF1F5C36)
        #expect(TileHue.green.fillARGB(.dark) == 0xFF1C3526)
        #expect(TileHue.green.inkARGB(.dark) == 0xFF94D2AA)
    }

    @Test("Red hue ARGB values")
    func redHueColors() {
        #expect(TileHue.red.fillARGB(.light) == 0xFFFBDDDD)
        #expect(TileHue.red.inkARGB(.light) == 0xFF8C1D1D)
        #expect(TileHue.red.fillARGB(.dark) == 0xFF452023)
        #expect(TileHue.red.inkARGB(.dark) == 0xFFF2A3A3)
    }

    @Test("Amber hue ARGB values")
    func amberHueColors() {
        #expect(TileHue.amber.fillARGB(.light) == 0xFFFBEED3)
        #expect(TileHue.amber.inkARGB(.light) == 0xFF7A4A00)
        #expect(TileHue.amber.fillARGB(.dark) == 0xFF3F3015)
        #expect(TileHue.amber.inkARGB(.dark) == 0xFFF0C873)
    }

    @Test("Neutral hue ARGB values")
    func neutralHueColors() {
        #expect(TileHue.neutral.fillARGB(.light) == 0xFFECE8E2)
        #expect(TileHue.neutral.inkARGB(.light) == 0xFF4A4540)
        #expect(TileHue.neutral.fillARGB(.dark) == 0xFF34312E)
        #expect(TileHue.neutral.inkARGB(.dark) == 0xFFD3CCC4)
    }
}
