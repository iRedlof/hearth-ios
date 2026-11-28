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

@Suite("Widget page preview source")
struct WidgetPreviewSourceTests {
    @Test("Not set up is always an example")
    func notSetUp() {
        #expect(widgetPreviewSource(isSetUp: false, supportsLive: true, hasLiveData: true) == .example)
        #expect(widgetPreviewSource(isSetUp: false, supportsLive: false, hasLiveData: false) == .example)
    }

    @Test("A set-up kind without a live source stays an example")
    func noLiveSource() {
        #expect(widgetPreviewSource(isSetUp: true, supportsLive: false, hasLiveData: false) == .example)
    }

    @Test("A set-up kind waits for its own data instead of showing made-up data")
    func waitsForOwnData() {
        #expect(widgetPreviewSource(isSetUp: true, supportsLive: true, hasLiveData: false) == .loading)
    }

    @Test("A set-up kind with data is live")
    func live() {
        #expect(widgetPreviewSource(isSetUp: true, supportsLive: true, hasLiveData: true) == .live)
    }

    @Test("Only a live preview may claim to be on the home screen")
    func caption() {
        #expect(widgetPreviewCaption(.example, status: "On your home screen · updated 8:54 PM")
            == "Example · your widget shows your own data")
        #expect(widgetPreviewCaption(.example, status: "On your home screen")
            == "Example · your widget shows your own data")
        #expect(widgetPreviewCaption(.loading, status: "On your home screen") == "Loading your widget…")
        #expect(widgetPreviewCaption(.live, status: "On your home screen · updated 8:54 PM")
            == "On your home screen · updated 8:54 PM")
        // A warning or the not-set-up line is already honest and is never replaced.
        #expect(widgetPreviewCaption(.example, status: "Example · yours appears after setup")
            == "Example · yours appears after setup")
        #expect(widgetPreviewCaption(.example, status: "Home Assistant is offline") == "Home Assistant is offline")
        #expect(widgetPreviewCaption(.loading, status: "Updates paused") == "Updates paused")
    }
}
