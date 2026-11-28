import Testing
@testable import HearthKit

@Suite("Home Screen widget size")
struct HomeScreenWidgetSizeTests {
    private func size(_ screenWidth: Double) -> HomeScreenWidgetSize { homeScreenWidgetSize(screenWidth: screenWidth) }

    @Test("Each iPhone width gets Apple's medium widget size")
    func table() {
        #expect(size(430) == HomeScreenWidgetSize(width: 364, height: 170))
        #expect(size(428) == HomeScreenWidgetSize(width: 364, height: 170))
        #expect(size(414) == HomeScreenWidgetSize(width: 360, height: 169))
        #expect(size(393) == HomeScreenWidgetSize(width: 338, height: 158))
        #expect(size(390) == HomeScreenWidgetSize(width: 338, height: 158))
        #expect(size(375) == HomeScreenWidgetSize(width: 329, height: 155))
        #expect(size(320) == HomeScreenWidgetSize(width: 292, height: 141))
    }

    @Test("Wider than any known phone uses the largest size; narrower uses the smallest")
    func edges() {
        #expect(size(500) == HomeScreenWidgetSize(width: 364, height: 170))
        #expect(size(0) == HomeScreenWidgetSize(width: 292, height: 141))
    }
}
