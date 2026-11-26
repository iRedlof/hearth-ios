import Testing
@testable import HearthKit

@Suite("CpAlerts helpers")
struct CpAlertsTests {

    @Test("whileAutoRunsEnabled when auto is ON")
    func whileAutoRunsEnabledOn() {
        #expect(whileAutoRunsEnabled(autoOn: true) == true)
    }

    @Test("whileAutoRunsEnabled when auto is OFF")
    func whileAutoRunsEnabledOff() {
        #expect(whileAutoRunsEnabled(autoOn: false) == false)
    }

    @Test("cpAlertEditKey maps yourTurn to offer")
    func editKeyYourTurn() {
        #expect(cpAlertEditKey(.yourTurn) == "offer")
    }

    @Test("cpAlertEditKey maps acceptedHeld to accepted")
    func editKeyAcceptedHeld() {
        #expect(cpAlertEditKey(.acceptedHeld) == "accepted")
    }

    @Test("cpAlertEditKey maps snoozed to snoozed")
    func editKeySnoozed() {
        #expect(cpAlertEditKey(.snoozed) == "snoozed")
    }

    @Test("cpAlertEditKey maps secondOffer to second")
    func editKeySecondOffer() {
        #expect(cpAlertEditKey(.secondOffer) == "second")
    }
}
