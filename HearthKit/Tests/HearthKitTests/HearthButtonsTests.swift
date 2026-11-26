import Testing
@testable import HearthKit

@Suite("HearthButtons Tests")
struct HearthButtonsTests {
    @Test("Button heights from metrics") @MainActor
    func buttonHeightsFromMetrics() {
        #expect(InkButtonStyle.height == HearthMetrics.buttonH)
        #expect(InlineRowButtonStyle.height == HearthMetrics.buttonHSmall)
    }
}
