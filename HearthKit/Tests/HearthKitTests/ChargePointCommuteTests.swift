import XCTest
@testable import HearthKit

/**
 The commute auto-join decision is a pure function over HA's two booleans + ChargePoint run state +
 once-per-morning debounce dates. All timing/zone/ETA logic lives in Home Assistant; this only branches.
 Ported 1:1 from Android `ChargePointCommuteTest.kt`.
 */
final class ChargePointCommuteTests: XCTestCase {
    private let today: CommuteDay = 20261027      // Oct 27, 2026 (yyyymmdd)
    private let yesterday: CommuteDay = 20261026  // Oct 26, 2026

    /// Helper to call `commuteDecide` with defaults.
    private func decide(
        autojoinEnabled: Bool = false,
        checkBeforeLeaveEnabled: Bool = false,
        chargeNow: Bool = false,
        signinNeeded: Bool = false,
        armed: Bool = false,
        charging: Bool = false,
        signedOutOrExpired: Bool = false,
        lastArmDay: CommuteDay? = nil,
        lastNotifyDay: CommuteDay? = nil
    ) -> CommuteAction {
        commuteDecide(
            autojoinEnabled: autojoinEnabled,
            checkBeforeLeaveEnabled: checkBeforeLeaveEnabled,
            chargeNow: chargeNow,
            signinNeeded: signinNeeded,
            alreadyArmed: armed,
            charging: charging,
            signedOutOrExpired: signedOutOrExpired,
            lastArmDay: lastArmDay,
            lastNotifyDay: lastNotifyDay,
            today: today
        )
    }

    func testBothDisabledDoesNothingEvenWhenEverythingElseSaysGo() {
        XCTAssertEqual(.none, decide(autojoinEnabled: false, checkBeforeLeaveEnabled: false, chargeNow: true, signinNeeded: true))
    }

    // MARK: - Auto-join branch tests (autojoinEnabled gates armAuto)

    func testAutojoinEnabledInRangeAndSignedInArmsTheAutoRun() {
        XCTAssertEqual(.armAuto, decide(autojoinEnabled: true, chargeNow: true, signinNeeded: true))
    }

    func testAutojoinEnabledAlreadyArmedDoesNotReArm() {
        XCTAssertEqual(.none, decide(autojoinEnabled: true, chargeNow: true, signinNeeded: true, armed: true))
    }

    func testAutojoinEnabledChargingDoesNotArm() {
        XCTAssertEqual(.none, decide(autojoinEnabled: true, chargeNow: true, signinNeeded: true, charging: true))
    }

    func testAutojoinEnabledArmsAtMostOncePerMorning() {
        XCTAssertEqual(.none, decide(autojoinEnabled: true, chargeNow: true, signinNeeded: true, lastArmDay: today))
        XCTAssertEqual(.armAuto, decide(autojoinEnabled: true, chargeNow: true, signinNeeded: true, lastArmDay: yesterday))
    }

    func testAutojoinDisabledDoesNotArmEvenWhenConditionsMet() {
        XCTAssertEqual(.none, decide(autojoinEnabled: false, chargeNow: true))
    }

    // MARK: - Check-before-leave branch tests (checkBeforeLeaveEnabled gates notifySignIn)

    func testCheckBeforeLeaveEnabledSignedOutWhileApproachingNudgesToSignIn() {
        XCTAssertEqual(.notifySignIn, decide(checkBeforeLeaveEnabled: true, chargeNow: true, signinNeeded: true, signedOutOrExpired: true))
    }

    func testCheckBeforeLeaveEnabledNudgesAtMostOncePerMorning() {
        XCTAssertEqual(.none, decide(checkBeforeLeaveEnabled: true, signinNeeded: true, signedOutOrExpired: true, lastNotifyDay: today))
        XCTAssertEqual(.notifySignIn, decide(checkBeforeLeaveEnabled: true, signinNeeded: true, signedOutOrExpired: true, lastNotifyDay: yesterday))
    }

    func testCheckBeforeLeaveDisabledDoesNotNotifyEvenWhenConditionsMet() {
        XCTAssertEqual(.none, decide(checkBeforeLeaveEnabled: false, signinNeeded: true, signedOutOrExpired: true))
    }

    // MARK: - Branch independence tests

    func testAutojoinEnabledDoesNotNotifyEvenWhenNotifyConditionsMet() {
        // Auto-join enabled, signed out, signin needed → does NOT notify (notify branch disabled)
        XCTAssertEqual(.none, decide(autojoinEnabled: true, checkBeforeLeaveEnabled: false, signinNeeded: true, signedOutOrExpired: true))
    }

    func testCheckBeforeLeaveEnabledDoesNotArmEvenWhenArmConditionsMet() {
        // Check-before-leave enabled, signed in, charge now → does NOT arm (arm branch disabled)
        XCTAssertEqual(.none, decide(autojoinEnabled: false, checkBeforeLeaveEnabled: true, chargeNow: true))
    }

    func testSignedInButOnlyWithinTheWiderNudgeWindowNotYet30MinDoesNothing() {
        XCTAssertEqual(.none, decide(autojoinEnabled: true, chargeNow: false, signinNeeded: true))
    }

    func testSignedOutButNotYetWithinTheNudgeWindowDoesNothing() {
        XCTAssertEqual(.none, decide(checkBeforeLeaveEnabled: true, signinNeeded: false, signedOutOrExpired: true))
    }

    // MARK: - Commute Sensor Parser Tests

    func testParseProductionCapitalizedTrueFalse() {
        let result = parseCommuteSensors("True|False")
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.chargeNow, true)
        XCTAssertEqual(result?.signinNeeded, false)
    }

    func testParseProductionCapitalizedFalseTrue() {
        let result = parseCommuteSensors("False|True")
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.chargeNow, false)
        XCTAssertEqual(result?.signinNeeded, true)
    }

    func testParseProductionCapitalizedTrueTrue() {
        let result = parseCommuteSensors("True|True")
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.chargeNow, true)
        XCTAssertEqual(result?.signinNeeded, true)
    }

    func testParseProductionCapitalizedFalseFalse() {
        let result = parseCommuteSensors("False|False")
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.chargeNow, false)
        XCTAssertEqual(result?.signinNeeded, false)
    }

    func testParseWithTrailingNewline() {
        let result = parseCommuteSensors("True|False\n")
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.chargeNow, true)
        XCTAssertEqual(result?.signinNeeded, false)
    }

    func testParseWithSurroundingWhitespace() {
        let result = parseCommuteSensors(" True | False ")
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.chargeNow, true)
        XCTAssertEqual(result?.signinNeeded, false)
    }

    func testParseLowercaseCaseInsensitive() {
        let result = parseCommuteSensors("true|false")
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.chargeNow, true)
        XCTAssertEqual(result?.signinNeeded, false)
    }

    func testParseMixedCaseCaseInsensitive() {
        let result = parseCommuteSensors("TrUe|FaLsE")
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.chargeNow, true)
        XCTAssertEqual(result?.signinNeeded, false)
    }

    func testParseMalformedSingleToken() {
        XCTAssertNil(parseCommuteSensors("True"))
    }

    func testParseMalformedThreeTokens() {
        XCTAssertNil(parseCommuteSensors("True|False|extra"))
    }

    func testParseMalformedEmptyString() {
        XCTAssertNil(parseCommuteSensors(""))
    }

    func testParseNonTrueTokensMapToFalse() {
        // Android semantics: anything that isn't "true" (case-insensitive) → false
        let result = parseCommuteSensors("on|off")
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.chargeNow, false)
        XCTAssertEqual(result?.signinNeeded, false)
    }

    // MARK: - Commute Sensor Fetch Tests

    func testFetchReturnsNilWhenConfigMissing() async {
        let result = await fetchCommuteSensors(nil, now: Date(), read: {
            XCTFail("A disconnected fetch must not request sensors")
            return "True|False"
        })
        XCTAssertNil(result)
    }

    func testFetchReturnsNilWhenConfigNotReady() async {
        // Config with empty token and no entityId is not carReady
        let config = HaConfig(baseUrl: "https://example.com", token: "", entityId: "")
        let result = await fetchCommuteSensors(config, now: Date(), read: {
            XCTFail("A not-ready fetch must not request sensors")
            return "True|False"
        })
        XCTAssertNil(result)
    }

    func testFetchReturnsValidResultWithTimestamp() async {
        let config = HaConfig(baseUrl: "https://example.com", token: "fixture", entityId: "sensor.car")
        let now = Date(timeIntervalSince1970: 1_793_399_400)
        let result = await fetchCommuteSensors(config, now: now, read: { "True|False" })
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.chargeNow, true)
        XCTAssertEqual(result?.signinNeeded, false)
        XCTAssertEqual(result?.lastHeard, now)
    }

    func testFetchReturnsNilOnMalformedResponse() async {
        let config = HaConfig(baseUrl: "https://example.com", token: "fixture", entityId: "sensor.car")
        let result = await fetchCommuteSensors(config, now: Date(), read: { "malformed" })
        XCTAssertNil(result)
    }

    func testFetchReturnsNilOnNetworkError() async {
        let config = HaConfig(baseUrl: "https://example.com", token: "fixture", entityId: "sensor.car")
        let result = await fetchCommuteSensors(config, now: Date(), read: {
            throw HaError("Network timeout")
        })
        XCTAssertNil(result)
    }
}
