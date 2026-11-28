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

@Suite("Widget page status names the right service")
struct WidgetPageServiceTests {
    @Test("ChargePoint problems name ChargePoint, not Home Assistant")
    func chargePoint() {
        #expect(widgetPageStatus(health: .needsSignIn, fresh: nil, isSetUp: true, service: "ChargePoint")
            == "Sign in to ChargePoint to update")
        #expect(widgetPageStatus(health: .error, fresh: nil, isSetUp: true, service: "ChargePoint")
            == "Couldn't update · check ChargePoint connection")
        #expect(widgetPageStatus(health: .stale, fresh: nil, isSetUp: true, service: "ChargePoint")
            == "Hasn't updated in a while · check ChargePoint connection")
        #expect(widgetPageStatus(health: .offline, fresh: nil, isSetUp: true, service: "ChargePoint")
            == "ChargePoint is offline")
    }

    @Test("Home Assistant stays the default")
    func defaultService() {
        #expect(widgetPageStatus(health: .needsSignIn, fresh: nil, isSetUp: true) == "Sign in to Home Assistant to update")
    }
}

@Suite("ChargePoint Home tile line")
struct CpTileLineTests {
    @Test("A number is shown with what it counts")
    func numberWithUnit() {
        #expect(cpTileStateLine(bigAnswer: "77", unit: "plugs free", stale: false) == "77 plugs free")
        #expect(cpTileStateLine(bigAnswer: "Your turn", unit: "to accept", stale: false) == "Your turn to accept")
    }

    @Test("No unit, no trailing space")
    func noUnit() {
        #expect(cpTileStateLine(bigAnswer: "Snoozed", unit: "", stale: false) == "Snoozed")
        #expect(cpTileStateLine(bigAnswer: "Snoozed", unit: "  ", stale: false) == "Snoozed")
    }

    @Test("Stale data says so")
    func stale() {
        #expect(cpTileStateLine(bigAnswer: "77", unit: "plugs free", stale: true) == "Stale data")
    }
}

@Suite("ChargePoint widget join choices")
struct CpJoinChoiceTests {
    private func snapshot(action: String, auto: CpAutoControl) -> CpSnapshot {
        var value = CpSnapshot.sample
        value.actionLabel = action; value.autoControl = auto
        return value
    }

    @Test("Not in line with Auto off offers both ways to join")
    func offersBoth() {
        #expect(snapshot(action: "Join", auto: .join).offersJoinWithAuto)
    }

    @Test("Auto already on, signed out, or nothing to join offers no second button")
    func single() {
        #expect(!snapshot(action: "Join", auto: .stop).offersJoinWithAuto)
        #expect(!snapshot(action: "Join", auto: .disabled).offersJoinWithAuto)
        #expect(!snapshot(action: "Join", auto: .signin).offersJoinWithAuto)
        #expect(!snapshot(action: "Open", auto: .join).offersJoinWithAuto)
        #expect(!snapshot(action: "Sign in", auto: .join).offersJoinWithAuto)
    }
}
