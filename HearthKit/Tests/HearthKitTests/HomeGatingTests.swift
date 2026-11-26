import Testing
@testable import HearthKit

@Suite("HomeGating Tests")
struct HomeGatingTests {

    @Test("Not connected shows Get-started")
    func notConnectedShowsGetStarted() {
        #expect(showGetStarted(haConnected: false, widgetCount: 0) == true)
        #expect(showGetStarted(haConnected: false, widgetCount: 5) == true)
    }

    @Test("Connected but zero widgets shows Get-started")
    func connectedZeroWidgetsShowsGetStarted() {
        #expect(showGetStarted(haConnected: true, widgetCount: 0) == true)
    }

    @Test("Connected with widgets hides Get-started")
    func connectedWithWidgetsHidesGetStarted() {
        #expect(showGetStarted(haConnected: true, widgetCount: 1) == false)
        #expect(showGetStarted(haConnected: true, widgetCount: 10) == false)
    }
}
