import Testing
@testable import HearthKit

@Suite("HearthButtons Tests")
struct HearthButtonsTests {
    @Test("Button heights from metrics")
    func buttonHeightsFromMetrics() {
        #expect(InkButtonStyle.height == HearthMetrics.buttonH)
        #expect(InlineRowButtonStyle.height == HearthMetrics.buttonHSmall)
    }
}
