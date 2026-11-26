import Testing
@testable import HearthKit

@Suite("Widget page status line")
struct WidgetPageStatusTests {

    @Test("Set up and OK with fresh data")
    func setUpOK() {
        let status = widgetPageStatus(health: .ok, fresh: "2 min ago", isSetUp: true)
        #expect(status == "On your home screen · updated 2 min ago")
    }

    @Test("Set up and OK without fresh data")
    func setUpOKNoFresh() {
        let status = widgetPageStatus(health: .ok, fresh: nil, isSetUp: true)
        #expect(status == "On your home screen")
    }

    @Test("Not set up shows example status")
    func notSetUp() {
        let status = widgetPageStatus(health: .setup, fresh: nil, isSetUp: false)
        #expect(status == "Example · yours appears after setup")
    }

    @Test("Stale health shows appropriate warning")
    func staleHealth() {
        let status = widgetPageStatus(health: .stale, fresh: "15 min ago", isSetUp: true)
        #expect(status == "Hasn't updated in a while · check Home Assistant connection")
    }

    @Test("Error health shows appropriate warning")
    func errorHealth() {
        let status = widgetPageStatus(health: .error, fresh: nil, isSetUp: true)
        #expect(status == "Couldn't update · check Home Assistant connection")
    }

    @Test("Needs sign-in health shows appropriate warning")
    func needsSignInHealth() {
        let status = widgetPageStatus(health: .needsSignIn, fresh: nil, isSetUp: true)
        #expect(status == "Sign in to Home Assistant to update")
    }

    @Test("Paused health shows appropriate message")
    func pausedHealth() {
        let status = widgetPageStatus(health: .paused, fresh: nil, isSetUp: true)
        #expect(status == "Updates paused")
    }

    @Test("Offline health shows appropriate warning")
    func offlineHealth() {
        let status = widgetPageStatus(health: .offline, fresh: nil, isSetUp: true)
        #expect(status == "Home Assistant is offline")
    }
}
