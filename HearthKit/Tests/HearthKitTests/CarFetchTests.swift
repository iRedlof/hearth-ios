import XCTest
@testable import HearthKit

final class CarFetchTests: XCTestCase {
    private let config = HaConfig(baseUrl: "https://example.com", token: "fixture", entityId: "")
    private let first = Date(timeIntervalSince1970: 1_800_000_000)
    private static func reply(_ battery: String = "79", prefix: String = "stargate",
                       limit: String = "90", sentry: String = "on") -> String {
        """
        {"found":true,"prefix":"\(prefix)","name":"Stargate","unit":"mi","s":{
        "sensor.battery_level":"\(battery)","number.charge_limit":"\(limit)",
        "switch.sentry_mode":"\(sentry)","lock.lock":"locked"}}
        """
    }

    func testMissingConfigUsesSetupWithoutRequestingOrShowingSample() async {
        let result = await fetchCarReadings(nil, now: first, request: {
            XCTFail("Setup must not send a request"); return Self.reply()
        })
        let snap = result.snapshot(now: first)
        XCTAssertTrue(result.setup)
        XCTAssertNil(snap.battery)
        XCTAssertEqual(snap.chargeLine, "Set up Home Assistant")
        XCTAssertEqual(snap.checkedAt, "—")
    }

    func testFailureKeepsSuccessfulReadingsTimeAndNeutralSentry() async {
        let old = await fetchCarReadings(config, now: first, request: { Self.reply() })
        let failed = await fetchCarReadings(config, previous: old.cache, now: first.addingTimeInterval(60),
            request: { throw URLError(.notConnectedToInternet) })
        let snap = failed.snapshot(now: first)
        XCTAssertEqual(failed.cache?.checkedAt, first)
        XCTAssertEqual(snap.battery, 79)
        XCTAssertEqual(snap.limit, 90)
        XCTAssertTrue(snap.stale)
        XCTAssertEqual(snap.tone, .offline)
        XCTAssertEqual(snap.chargeLine, "Can't connect")
        XCTAssertEqual(snap.error, "Can't reach Home Assistant")
        XCTAssertTrue(snap.place.contains("Last known"))
    }

    func testNoCarDoesNotResurrectLastGood() async {
        let old = await fetchCarReadings(config, now: first, request: { Self.reply() })
        let result = await fetchCarReadings(config, previous: old.cache, now: first.addingTimeInterval(60),
            request: { #"{"found":false}"# })
        XCTAssertNil(result.snapshot(now: first).battery)
        XCTAssertEqual(result.snapshot(now: first).chargeLine, "No car found")
        XCTAssertEqual(result.cache?.checkedAt, first.addingTimeInterval(60))
    }

    func testUnknownBatteryOnlyBorrowsSameVehicleReadings() async {
        let old = await fetchCarReadings(config, now: first, request: { Self.reply() })
        let same = await fetchCarReadings(config, previous: old.cache, now: first.addingTimeInterval(60),
            request: { Self.reply("unknown") })
        XCTAssertEqual(same.snapshot(now: first).battery, 79)
        XCTAssertTrue(same.snapshot(now: first).stale)
        let other = await fetchCarReadings(config, previous: old.cache, now: first.addingTimeInterval(60),
            request: { Self.reply("unknown", prefix: "other") })
        XCTAssertNil(other.snapshot(now: first).battery)
        XCTAssertFalse(other.snapshot(now: first).stale)
    }

    func testMalformedReplyIsFailureRatherThanSuccessfulNoCar() async {
        let old = await fetchCarReadings(config, now: first, request: { Self.reply() })
        for bad in ["not json", "{}", #"{"found":"false"}"#, #"{"found":true}"#] {
            let result = await fetchCarReadings(config, previous: old.cache, now: first.addingTimeInterval(60),
                request: { bad })
            XCTAssertNotNil(result.error)
            XCTAssertEqual(result.cache, old.cache)
            XCTAssertEqual(result.snapshot(now: first).battery, 79)
        }
    }

    func testMissingLimitAndBatteryRemainUnknownInSnapshot() async {
        let value = await fetchCarReadings(config, now: first,
            request: { Self.reply("unknown", limit: "unavailable", sentry: "unavailable") })
        let snap = value.snapshot(now: first)
        XCTAssertNil(snap.battery)
        XCTAssertNil(snap.limit)
        XCTAssertEqual(snap.sentry, .unknown)
        XCTAssertEqual(snap.tone, .offline)
    }

    func testFailedFirstFetchDoesNotInventTelemetryOrSuccessfulCheck() async {
        let result = await fetchCarReadings(config, now: first,
            request: { throw HaError("Sign-in rejected: check the token", code: 401) })
        let snap = result.snapshot(now: first)
        XCTAssertNil(snap.battery)
        XCTAssertNil(snap.limit)
        XCTAssertEqual(snap.checkedAt, "—")
        XCTAssertEqual(snap.chargeLine, "Sign in again")
        XCTAssertEqual(snap.error, "Sign-in rejected: check the token")
        XCTAssertTrue(snap.needsSettings)
        XCTAssertTrue(snap.needsSignIn)
        XCTAssertTrue(snap.stale)
    }

    func testRecoveryDistinguishesAuthenticationFromEntityAndNetworkErrors() {
        for error in ["Signed out: sign in again", "Sign-in failed (400)",
                      "Sign-in rejected: check the token"] {
            XCTAssertTrue(CarFetchResult(cache: nil, error: error).snapshot().needsSignIn)
        }
        for error in ["Can't reach Home Assistant", "Check the entity in Settings",
                      "Couldn't read car data"] {
            XCTAssertFalse(CarFetchResult(cache: nil, error: error).snapshot().needsSignIn)
        }
    }

    func testCacheEnvelopeRoundTripsAsOneRecord() async throws {
        let result = await fetchCarReadings(config, now: first, request: { Self.reply() })
        let encoded = try JSONEncoder().encode(XCTUnwrap(result.cache))
        XCTAssertEqual(try JSONDecoder().decode(CarReadingsCache.self, from: encoded), result.cache)
    }

    func testOverlappingUnknownReplyUsesNewestSameVehicleGoodReading() throws {
        let latest = try carReadingsAfterReply(Self.reply("84"), previous: nil, checkedAt: first)
        let unknown = try carReadingsAfterReply(Self.reply("unknown"), previous: latest,
            checkedAt: first.addingTimeInterval(60))
        XCTAssertEqual(CarFetchResult(cache: unknown).snapshot(now: first).battery, 84)
        XCTAssertEqual(unknown.lastGood, latest.current)
        let other = try carReadingsAfterReply(Self.reply("unknown", prefix: "other"), previous: latest,
            checkedAt: first.addingTimeInterval(60))
        XCTAssertNil(other.lastGood)
    }

    func testConnectionIdentityUsesEffectiveAuthAndIgnoresWidgetSelections() {
        var same = config
        same.baseUrl += "/"; same.climateId = "climate.other"
        same.refreshToken = "unused-oauth"
        XCTAssertTrue(haSameConnection(config, same))
        same.token = "different"
        XCTAssertFalse(haSameConnection(config, same))
        same = config; same.baseUrl = "https://other.example.com"
        XCTAssertFalse(haSameConnection(config, same))
        var oauth = config; oauth.token = ""; oauth.refreshToken = "account-a"
        var other = oauth; other.refreshToken = "account-b"
        XCTAssertFalse(haSameConnection(oauth, other))
    }
}
