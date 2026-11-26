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

    /// Helper to call `commuteDecide` with defaults, mirroring the Kotlin test helper.
    private func decide(
        enabled: Bool = true,
        chargeNow: Bool = false,
        signinNeeded: Bool = false,
        armed: Bool = false,
        charging: Bool = false,
        signedOutOrExpired: Bool = false,
        lastArmDay: CommuteDay? = nil,
        lastNotifyDay: CommuteDay? = nil
    ) -> CommuteAction {
        commuteDecide(
            enabled: enabled,
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

    func testDisabledDoesNothingEvenWhenEverythingElseSaysGo() {
        XCTAssertEqual(.none, decide(enabled: false, chargeNow: true, signinNeeded: true))
    }

    func testInRangeAndSignedInArmsTheAutoRun() {
        XCTAssertEqual(.armAuto, decide(chargeNow: true, signinNeeded: true))
    }

    func testAlreadyArmedDoesNotReArm() {
        XCTAssertEqual(.none, decide(chargeNow: true, signinNeeded: true, armed: true))
    }

    func testChargingDoesNotArm() {
        XCTAssertEqual(.none, decide(chargeNow: true, signinNeeded: true, charging: true))
    }

    func testArmsAtMostOncePerMorning() {
        XCTAssertEqual(.none, decide(chargeNow: true, signinNeeded: true, lastArmDay: today))
        XCTAssertEqual(.armAuto, decide(chargeNow: true, signinNeeded: true, lastArmDay: yesterday))
    }

    func testSignedOutWhileApproachingNudgesToSignInDoesNotArm() {
        XCTAssertEqual(.notifySignIn, decide(chargeNow: true, signinNeeded: true, signedOutOrExpired: true))
    }

    func testNudgesAtMostOncePerMorning() {
        XCTAssertEqual(.none, decide(signinNeeded: true, signedOutOrExpired: true, lastNotifyDay: today))
        XCTAssertEqual(.notifySignIn, decide(signinNeeded: true, signedOutOrExpired: true, lastNotifyDay: yesterday))
    }

    func testSignedInButOnlyWithinTheWiderNudgeWindowNotYet30MinDoesNothing() {
        XCTAssertEqual(.none, decide(chargeNow: false, signinNeeded: true))
    }

    func testSignedOutButNotYetWithinTheNudgeWindowDoesNothing() {
        XCTAssertEqual(.none, decide(signinNeeded: false, signedOutOrExpired: true))
    }

    // MARK: - Commute Sensor Parser Tests

    func testParseValidTrueFalse() {
        let result = parseCommuteSensors("true|false")
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.chargeNow, true)
        XCTAssertEqual(result?.signinNeeded, false)
    }

    func testParseValidFalseTrue() {
        let result = parseCommuteSensors("false|true")
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.chargeNow, false)
        XCTAssertEqual(result?.signinNeeded, true)
    }

    func testParseValidTrueTrue() {
        let result = parseCommuteSensors("true|true")
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.chargeNow, true)
        XCTAssertEqual(result?.signinNeeded, true)
    }

    func testParseValidFalseFalse() {
        let result = parseCommuteSensors("false|false")
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.chargeNow, false)
        XCTAssertEqual(result?.signinNeeded, false)
    }

    func testParseMalformedSingleToken() {
        XCTAssertNil(parseCommuteSensors("true"))
    }

    func testParseMalformedThreeTokens() {
        XCTAssertNil(parseCommuteSensors("true|false|extra"))
    }

    func testParseMalformedEmptyString() {
        XCTAssertNil(parseCommuteSensors(""))
    }

    func testParseMalformedNonBoolTokens() {
        XCTAssertNil(parseCommuteSensors("on|off"))
    }

    // MARK: - Commute Sensor Fetch Tests

    func testFetchReturnsNilWhenConfigMissing() async {
        let result = await fetchCommuteSensors(nil, now: Date(), read: {
            XCTFail("A disconnected fetch must not request sensors")
            return "true|false"
        })
        XCTAssertNil(result)
    }

    func testFetchReturnsNilWhenConfigNotReady() async {
        // Config with empty token and no entityId is not carReady
        let config = HaConfig(baseUrl: "https://example.com", token: "", entityId: "")
        let result = await fetchCommuteSensors(config, now: Date(), read: {
            XCTFail("A not-ready fetch must not request sensors")
            return "true|false"
        })
        XCTAssertNil(result)
    }

    func testFetchReturnsValidResultWithTimestamp() async {
        let config = HaConfig(baseUrl: "https://example.com", token: "fixture", entityId: "sensor.car")
        let now = Date(timeIntervalSince1970: 1_793_399_400)
        let result = await fetchCommuteSensors(config, now: now, read: { "true|false" })
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
