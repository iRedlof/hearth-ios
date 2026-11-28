import Testing
@testable import HearthKit

@Suite("Home Screen widget size")
struct HomeScreenWidgetSizeTests {
    @Test("Each iPhone width gets Apple's widget size")
    func table() {
        #expect(homeScreenWidgetSize(screenWidth: 430).medium == (364, 170))
        #expect(homeScreenWidgetSize(screenWidth: 428).large == (364, 382))
        #expect(homeScreenWidgetSize(screenWidth: 414).medium == (360, 169))
        #expect(homeScreenWidgetSize(screenWidth: 393).medium == (338, 158))
        #expect(homeScreenWidgetSize(screenWidth: 390).large == (338, 354))
        #expect(homeScreenWidgetSize(screenWidth: 375).medium == (329, 155))
        #expect(homeScreenWidgetSize(screenWidth: 320).medium == (292, 141))
    }

    @Test("Wider than any known phone uses the largest size; narrower uses the smallest")
    func edges() {
        #expect(homeScreenWidgetSize(screenWidth: 500).medium == (364, 170))
        #expect(homeScreenWidgetSize(screenWidth: 0).medium == (292, 141))
    }
}
