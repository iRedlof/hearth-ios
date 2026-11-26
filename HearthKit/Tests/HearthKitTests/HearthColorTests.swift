import Testing
@testable import HearthKit

@Suite("HearthColor ARGB constants")
struct HearthColorTests {

    @Test("page ARGB matches spec")
    func pageTokenMatchesSpec() {
        #expect(HearthColor.pageLight == 0xFFF5F3EF)
        #expect(HearthColor.pageDark == 0xFF111110)
    }

    @Test("ink ARGB matches spec")
    func inkTokenMatchesSpec() {
        #expect(HearthColor.inkLight == 0xFF1C1B19)
        #expect(HearthColor.inkDark == 0xFFF2EFEA)
    }

    @Test("card ARGB matches spec")
    func cardTokenMatchesSpec() {
        #expect(HearthColor.cardLight == 0xFFFFFFFF)
        #expect(HearthColor.cardDark == 0xFF1D1C1B)
    }

    @Test("green ARGB matches spec")
    func greenTokenMatchesSpec() {
        #expect(HearthColor.greenLight == 0xFF2E7D4F)
        #expect(HearthColor.greenDark == 0xFF7FD3A0)
    }

    @Test("greenBg ARGB matches spec")
    func greenBgTokenMatchesSpec() {
        #expect(HearthColor.greenBgLight == 0xFFE2F2E7)
        #expect(HearthColor.greenBgDark == 0xFF15301F)
    }

    @Test("amber ARGB matches spec")
    func amberTokenMatchesSpec() {
        #expect(HearthColor.amberLight == 0xFFA85F00)
        #expect(HearthColor.amberDark == 0xFFFFB54D)
    }

    @Test("amberBg ARGB matches spec")
    func amberBgTokenMatchesSpec() {
        #expect(HearthColor.amberBgLight == 0xFFFFF0D9)
        #expect(HearthColor.amberBgDark == 0xFF38270F)
    }

    @Test("red ARGB matches spec")
    func redTokenMatchesSpec() {
        #expect(HearthColor.redLight == 0xFFB3261E)
        #expect(HearthColor.redDark == 0xFFF2B8B5)
    }
}
