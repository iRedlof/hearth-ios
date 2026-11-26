import Testing
import SwiftUI
@testable import HearthKit

@Suite("ConnectionHero Presentation Mappers")
struct ConnectionHeroTests {

    // MARK: - Home Assistant Presentation

    @Test("HA connected status maps to ok tone")
    func haConnectedPresentation() {
        let result = haHeroPresentation(.connected)
        #expect(result.tone == .ok)
        #expect(result.word == "Connected")
        #expect(result.icon == "checkmark.circle.fill")
    }

    @Test("HA needs sign-in status maps to warn tone")
    func haNeedsSignInPresentation() {
        let result = haHeroPresentation(.needsSignIn)
        #expect(result.tone == .warn)
        #expect(result.word == "Needs sign-in")
        #expect(result.icon == "lock.fill")
    }

    @Test("HA not set up status maps to neutral tone")
    func haNotSetUpPresentation() {
        let result = haHeroPresentation(.notSetUp)
        #expect(result.tone == .neutral)
        #expect(result.word == "Not set up")
        #expect(result.icon == "house.fill")
    }

    // MARK: - ChargePoint Presentation

    @Test("CP connected status maps to ok tone")
    func cpConnectedPresentation() {
        let result = cpHeroPresentation(.connected)
        #expect(result.tone == .ok)
        #expect(result.word == "Connected")
        #expect(result.icon == "checkmark.circle.fill")
    }

    @Test("CP needs sign-in status maps to warn tone")
    func cpNeedsSignInPresentation() {
        let result = cpHeroPresentation(.needsSignIn)
        #expect(result.tone == .warn)
        #expect(result.word == "Needs sign-in")
        #expect(result.icon == "lock.fill")
    }

    @Test("CP not set up status maps to neutral tone")
    func cpNotSetUpPresentation() {
        let result = cpHeroPresentation(.notSetUp)
        #expect(result.tone == .neutral)
        #expect(result.word == "Not set up")
        #expect(result.icon == "bolt.car.fill")
    }

    // MARK: - Special States

    @Test("HA offline maps to neutral tone")
    func haOfflinePresentation() {
        let result = haHeroOffline()
        #expect(result.tone == .neutral)
        #expect(result.word == "Offline")
        #expect(result.icon == "cloud.slash.fill")
    }

    @Test("HA connection check OK maps to ok tone")
    func haCheckOKPresentation() {
        let result = haHeroCheckOK()
        #expect(result.tone == .ok)
        #expect(result.word == "Connection OK")
        #expect(result.icon == "checkmark.circle.fill")
    }
}
