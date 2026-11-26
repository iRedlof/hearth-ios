import Testing
@testable import HearthKit

@Suite("WidgetHealth Tests")
struct WidgetHealthTests {

    // MARK: - Ordering

    @Test("error > ok")
    func errorGreaterThanOk() {
        #expect(WidgetHealth.error > WidgetHealth.ok)
    }

    @Test("needsSignIn > stale")
    func needsSignInGreaterThanStale() {
        #expect(WidgetHealth.needsSignIn > WidgetHealth.stale)
    }

    @Test("setup > stale")
    func setupGreaterThanStale() {
        #expect(WidgetHealth.setup > WidgetHealth.stale)
    }

    @Test("sortsFirst is false only for ok")
    func sortsFirstOnlyForNonOk() {
        #expect(WidgetHealth.ok.sortsFirst == false)
        #expect(WidgetHealth.error.sortsFirst == true)
        #expect(WidgetHealth.stale.sortsFirst == true)
        #expect(WidgetHealth.needsSignIn.sortsFirst == true)
    }

    // MARK: - Tile Mapping

    @Test("tile .setup maps to .setup")
    func tileSetup() {
        #expect(widgetHealth(tile: .setup, hasError: false) == .setup)
    }

    @Test("tile .choose maps to .setup")
    func tileChoose() {
        #expect(widgetHealth(tile: .choose, hasError: false) == .setup)
    }

    @Test("tile .loading maps to .stale")
    func tileLoading() {
        #expect(widgetHealth(tile: .loading, hasError: false) == .stale)
    }

    @Test("tile .ready maps to .ok")
    func tileReady() {
        #expect(widgetHealth(tile: .ready, hasError: false) == .ok)
    }

    @Test("tile .empty maps to .ok")
    func tileEmpty() {
        #expect(widgetHealth(tile: .empty, hasError: false) == .ok)
    }

    @Test("tile .failed maps to .error")
    func tileFailed() {
        #expect(widgetHealth(tile: .failed, hasError: false) == .error)
    }

    @Test("tile .ready with hasError maps to .error")
    func tileReadyWithError() {
        #expect(widgetHealth(tile: .ready, hasError: true) == .error)
    }

    // MARK: - Beacon Precedence

    @Test("beacon error beats all")
    func beaconErrorPrecedence() {
        #expect(widgetHealth(stale: true, error: true, needsSettings: true, needsSignIn: true) == .error)
        #expect(widgetHealth(stale: false, error: true, needsSettings: false, needsSignIn: false) == .error)
    }

    @Test("beacon needsSignIn beats setup and stale")
    func beaconNeedsSignInPrecedence() {
        #expect(widgetHealth(stale: true, error: false, needsSettings: true, needsSignIn: true) == .needsSignIn)
        #expect(widgetHealth(stale: false, error: false, needsSettings: false, needsSignIn: true) == .needsSignIn)
    }

    @Test("beacon needsSettings beats stale")
    func beaconNeedsSettingsPrecedence() {
        #expect(widgetHealth(stale: true, error: false, needsSettings: true, needsSignIn: false) == .setup)
        #expect(widgetHealth(stale: false, error: false, needsSettings: true, needsSignIn: false) == .setup)
    }

    @Test("beacon stale when only stale is true")
    func beaconStalePrecedence() {
        #expect(widgetHealth(stale: true, error: false, needsSettings: false, needsSignIn: false) == .stale)
    }

    @Test("beacon all false maps to .ok")
    func beaconAllFalse() {
        #expect(widgetHealth(stale: false, error: false, needsSettings: false, needsSignIn: false) == .ok)
    }

    // MARK: - Most Urgent

    @Test("mostUrgent with empty array returns .ok")
    func mostUrgentEmpty() {
        #expect(mostUrgent([]) == .ok)
    }

    @Test("mostUrgent returns highest severity")
    func mostUrgentReturnsMax() {
        #expect(mostUrgent([.ok, .stale, .error]) == .error)
        #expect(mostUrgent([.ok, .stale]) == .stale)
        #expect(mostUrgent([.needsSignIn, .setup, .stale]) == .needsSignIn)
    }
}
