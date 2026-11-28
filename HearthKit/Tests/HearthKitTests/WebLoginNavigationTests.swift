import Testing
import Foundation
@testable import HearthKit

@Suite("Web login navigation stays inside the web view")
struct WebLoginNavigationTests {
    private func decide(_ target: String?) -> WebLoginNavigationDecision {
        webLoginNavigationDecision(target: target.flatMap(URL.init(string:)))
    }

    @Test("Every web navigation is kept in the web view, including hosts the ChargePoint app claims")
    func webNavigations() {
        #expect(decide("https://sso.chargepoint.com/") == .keepInWebView)
        #expect(decide("https://driver.chargepoint.com/home") == .keepInWebView)
        #expect(decide("https://na.chargepoint.com/driver/portal?x=1#top") == .keepInWebView)
        #expect(decide("http://example.com/") == .keepInWebView)
        #expect(decide("HTTPS://DRIVER.CHARGEPOINT.COM/home") == .keepInWebView)
    }

    @Test("Schemes that would launch another app are blocked")
    func appSchemes() {
        #expect(decide("chargepoint://home") == .block)
        #expect(decide("itms-apps://apps.apple.com/app/id356866743") == .block)
        #expect(decide("tel:5551234567") == .block)
        #expect(decide("mailto:someone@example.com") == .block)
    }

    @Test("Page-internal schemes and missing URLs are left alone")
    func internalSchemes() {
        #expect(decide("about:blank") == .allow)
        #expect(decide("blob:https://sso.chargepoint.com/1234") == .allow)
        #expect(decide("data:text/html,hello") == .allow)
        #expect(decide(nil) == .allow)
    }
}
