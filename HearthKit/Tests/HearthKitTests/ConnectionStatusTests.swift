import Testing
import SwiftUI
@testable import HearthKit

@Suite("Connection Status Tests")
struct ConnectionStatusTests {

    // MARK: - HA Connection Status

    @Test("HA not set up when baseUrl is blank")
    func haNotSetUpWhenBaseUrlBlank() {
        let config = HaConfig(baseUrl: "", token: "", entityId: "", refreshToken: "someToken")
        let status = haConnectionStatus(config)
        #expect(status == .notSetUp)
        #expect(status.tone == .neutral)
        #expect(status.label == "Not set up")
    }

    @Test("HA not set up when baseUrl is whitespace only")
    func haNotSetUpWhenBaseUrlWhitespace() {
        let config = HaConfig(baseUrl: "   ", token: "", entityId: "", refreshToken: "someToken")
        let status = haConnectionStatus(config)
        #expect(status == .notSetUp)
        #expect(status.tone == .neutral)
        #expect(status.label == "Not set up")
    }

    @Test("HA needs sign-in when baseUrl exists but not signed in")
    func haNeedsSignInWhenNotSignedIn() {
        let config = HaConfig(baseUrl: "https://example.com", token: "", entityId: "", refreshToken: "")
        let status = haConnectionStatus(config)
        #expect(status == .needsSignIn)
        #expect(status.tone == .warn)
        #expect(status.label == "Needs sign-in")
    }

    @Test("HA connected when baseUrl exists and signed in")
    func haConnectedWhenSignedIn() {
        let config = HaConfig(baseUrl: "https://example.com", token: "", entityId: "", refreshToken: "someToken")
        let status = haConnectionStatus(config)
        #expect(status == .connected)
        #expect(status.tone == .ok)
        #expect(status.label == "Connected")
    }

    // MARK: - ChargePoint Connection Status

    @Test("CP not set up when not signed in and no account")
    func cpNotSetUpWhenNoAccountOrSignIn() {
        let status = cpConnectionStatus(signedIn: false, hasAccount: false)
        #expect(status == .notSetUp)
        #expect(status.tone == .neutral)
        #expect(status.label == "Not set up")
    }

    @Test("CP needs sign-in when has account but not signed in")
    func cpNeedsSignInWhenHasAccountButNotSignedIn() {
        let status = cpConnectionStatus(signedIn: false, hasAccount: true)
        #expect(status == .needsSignIn)
        #expect(status.tone == .warn)
        #expect(status.label == "Needs sign-in")
    }

    @Test("CP connected when signed in")
    func cpConnectedWhenSignedIn() {
        let status = cpConnectionStatus(signedIn: true, hasAccount: false)
        #expect(status == .connected)
        #expect(status.tone == .ok)
        #expect(status.label == "Connected")
    }

    @Test("CP connected when signed in with account")
    func cpConnectedWhenSignedInWithAccount() {
        let status = cpConnectionStatus(signedIn: true, hasAccount: true)
        #expect(status == .connected)
        #expect(status.tone == .ok)
        #expect(status.label == "Connected")
    }

    // MARK: - Tone Verification (never swapped)

    @Test("connected always maps to ok tone")
    func connectedAlwaysMapsToOk() {
        // HA connected
        let haConfig = HaConfig(baseUrl: "https://example.com", token: "", entityId: "", refreshToken: "token")
        let haStatus = haConnectionStatus(haConfig)
        #expect(haStatus == .connected)
        #expect(haStatus.tone == .ok)

        // CP connected
        let cpStatus = cpConnectionStatus(signedIn: true, hasAccount: true)
        #expect(cpStatus == .connected)
        #expect(cpStatus.tone == .ok)
    }

    @Test("needsSignIn always maps to warn tone")
    func needsSignInAlwaysMapsToWarn() {
        // HA needs sign-in
        let haConfig = HaConfig(baseUrl: "https://example.com", token: "", entityId: "", refreshToken: "")
        let haStatus = haConnectionStatus(haConfig)
        #expect(haStatus == .needsSignIn)
        #expect(haStatus.tone == .warn)

        // CP needs sign-in
        let cpStatus = cpConnectionStatus(signedIn: false, hasAccount: true)
        #expect(cpStatus == .needsSignIn)
        #expect(cpStatus.tone == .warn)
    }
}
