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

    @Test("Green hue ARGB values")
    func greenHueColors() {
        #expect(TileHue.green.fillARGB(.light) == 0xFFDDF0E3)
        #expect(TileHue.green.inkARGB(.light) == 0xFF1F5C36)
        #expect(TileHue.green.fillARGB(.dark) == 0xFF1C3526)
        #expect(TileHue.green.inkARGB(.dark) == 0xFF94D2AA)
    }
}
