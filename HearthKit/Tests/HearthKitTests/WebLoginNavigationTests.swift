import Testing
import Foundation
@testable import HearthKit

@Suite("Web login navigation stays inside the web view")
struct WebLoginNavigationTests {
    private func decide(
        from current: String?, to target: String?, mainFrame: Bool = true,
        method: String? = "GET", reissue: Bool = false
    ) -> WebLoginNavigationDecision {
        webLoginNavigationDecision(
            currentHost: current, target: target.flatMap(URL.init(string:)),
            isMainFrame: mainFrame, method: method, isReissue: reissue
        )
    }

    @Test("The first load is allowed")
    func initialLoad() {
        #expect(decide(from: nil, to: "https://sso.chargepoint.com/") == .allow)
    }

    @Test("Moving to a host the ChargePoint app claims is reloaded in place")
    func crossHostAfterSignIn() {
        #expect(decide(from: "sso.chargepoint.com", to: "https://driver.chargepoint.com/home") == .reloadInPlace)
        #expect(decide(from: "sso.chargepoint.com", to: "https://na.chargepoint.com/home") == .reloadInPlace)
    }

    @Test("The reload it triggers is then allowed, so there is no loop")
    func reissueIsAllowed() {
        #expect(decide(from: "sso.chargepoint.com", to: "https://driver.chargepoint.com/home", reissue: true) == .allow)
    }

    @Test("Same-host navigation is left alone")
    func sameHost() {
        #expect(decide(from: "sso.chargepoint.com", to: "https://sso.chargepoint.com/login") == .allow)
        #expect(decide(from: "SSO.ChargePoint.com", to: "https://sso.chargepoint.com/login") == .allow)
    }

    @Test("Form posts and sub-frames are left alone")
    func postsAndFrames() {
        #expect(decide(from: "sso.chargepoint.com", to: "https://na.chargepoint.com/auth", method: "POST") == .allow)
        #expect(decide(from: "sso.chargepoint.com", to: "https://ads.example.com/frame", mainFrame: false) == .allow)
    }

    @Test("A missing method counts as GET")
    func nilMethod() {
        #expect(decide(from: "sso.chargepoint.com", to: "https://driver.chargepoint.com/home", method: nil) == .reloadInPlace)
    }

    @Test("App schemes are blocked; page-internal schemes are allowed")
    func schemes() {
        #expect(decide(from: "sso.chargepoint.com", to: "chargepoint://home") == .block)
        #expect(decide(from: "sso.chargepoint.com", to: "itms-apps://apps.apple.com/app/id356866743") == .block)
        #expect(decide(from: "sso.chargepoint.com", to: "about:blank") == .allow)
        #expect(decide(from: "sso.chargepoint.com", to: nil) == .allow)
    }
}
