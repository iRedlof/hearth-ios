import XCTest
import CoreGraphics
@testable import HearthKit

/// The beacon split must match Android `beaconMetrics` — a fixed ~37% hero, never 50/50.
final class BeaconLayoutTests: XCTestCase {
    func testReferenceSplitMatchesAndroid() {
        let s = beaconSplit(width: 352)   // the 352×222 reference
        XCTAssertEqual(s.rail, 130, accuracy: 0.5)
        XCTAssertEqual(s.inset, 12, accuracy: 0.5)
        XCTAssertEqual(s.panel, 198, accuracy: 0.5)
        XCTAssertEqual(s.leftPad, 14, accuracy: 0.5)
    }

    func testHeroIsAboutThirtySevenPercentNotHalf() {
        for w in [CGFloat(300), 320, 352, 380] {
            let ratio = beaconSplit(width: w).rail / w
            XCTAssertEqual(ratio, 0.369, accuracy: 0.01, "hero should be ~37% of width at \(w), not 50%")
        }
    }

    func testScalesDownBelowReference() {
        let s = beaconSplit(width: 320)   // sx = 320/352 ≈ 0.909
        XCTAssertEqual(s.rail, 118.2, accuracy: 0.5)
        XCTAssertEqual(s.panel, 180.0, accuracy: 1.0)
    }

    func testRailGrowsTowardMaxWidth() {
        let s = beaconSplit(width: 403)   // t = 1, sx = 1 → rail = 146
        XCTAssertEqual(s.rail, 146, accuracy: 0.5)
        XCTAssertEqual(s.inset, 14, accuracy: 0.5)
    }
}
