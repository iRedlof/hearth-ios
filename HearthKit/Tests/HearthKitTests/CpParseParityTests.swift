import Foundation
import XCTest
@testable import HearthKit

/// Parity with the Android app's tolerant ChargePoint parsing (the source of truth), built from the
/// response bodies embedded in Android's own tests. Plus coverage that a parse failure now identifies
/// itself (request + host + the 2xx status + a structural, secret-free reason).
final class CpParseParityTests: XCTestCase {

    // MARK: - Full realistic status reply (Android ChargePointStateTest "an offer…")

    func testFullAcceptPendingOfferReplyParses() throws {
        let raw = """
        {"user_status":{"waitlist":{"state":{"state":"ACCEPT_PENDING","regionId":0,\
        "currentTimeUTC":1792372115,"startTimeUTC":1792372024,"deviceId":16235001,"duration":1200,\
        "token":"T0K3N","portNo":1},"stations":[{"deviceId":13104611,"name":"MG MG-7 P2"},\
        {"deviceId":16235001,"name":"MG MG-29 P3"}]}}}
        """
        let value = try cpOwnedObservation(statusJson: raw)
        XCTAssertEqual(value.identity.phase, "ACCEPT_PENDING")
        XCTAssertEqual(value.identity.stationIDs, [13104611, 16235001])
        XCTAssertEqual(value.identity.deviceID, 16235001)
        XCTAssertEqual(value.identity.port, 1)
        XCTAssertEqual(value.identity.token, "T0K3N")
        XCTAssertEqual(value.identity.startMs, 1792372024 * 1000)
        XCTAssertEqual(value.identity.deadlineMs, (1792372024 + 1200) * 1000)
        XCTAssertNil(value.identity.sessionID)
    }

    // MARK: - Numeric fields delivered as strings (Android optLong/optInt coerce)

    func testNumericStatusFieldsDeliveredAsStringsAreCoerced() throws {
        let charging = try cpOwnedObservation(statusJson:
            "{\"user_status\":{\"charging\":{\"sessionId\":\"5633159011\",\"state\":\"in_use\"}}}")
        XCTAssertEqual(charging.identity.sessionID, 5633159011)

        let offer = try cpOwnedObservation(statusJson: """
        {"user_status":{"waitlist":{"state":{"state":"ACCEPT_PENDING","deviceId":"16235001",\
        "portNo":"1","token":"T0K3N","startTimeUTC":"1792372024","duration":"1200"},\
        "stations":[{"deviceId":"16235001"}]}}}
        """)
        XCTAssertEqual(offer.identity.deviceID, 16235001)
        XCTAssertEqual(offer.identity.port, 1)
        XCTAssertEqual(offer.identity.stationIDs, [16235001])
        XCTAssertEqual(offer.identity.startMs, 1792372024 * 1000)
    }

    // MARK: - Station list (Android cpStationsFrom): status_v2 fallback, counts, empty list

    func testStatusV2FallsBackToStatusLikeAndroid() {
        let stations = cpStationsFrom(
            "{\"map_data\":{\"stations\":[{\"device_id\":9,\"lat\":1,\"lon\":1,\"ports\":[{\"status\":\"available\"},{\"status\":\"in_use\"}]}]}}")
        XCTAssertEqual(stations.first?.free, 1)
        XCTAssertEqual(stations.first?.inUse, 1)
    }

    func testRealisticMultiPortStationCountsMatchAndroid() throws {
        let raw = """
        {"map_data":{"stations":[
        {"device_id":1,"address1":"2121 7th Ave","name1":"MG1","name2":"MG1 - 1 P3","lat":47.6164,"lon":-122.3387,"waitlist_allowed":true,"ports":[{"status_v2":"available"},{"status_v2":"in_use"}]},
        {"device_id":2,"address1":"2121 7th Ave","name1":"MG1","name2":"MG1-15 P3","lat":47.6164,"lon":-122.3387,"waitlist_allowed":true,"ports":[{"status_v2":"available"},{"status_v2":"available"}]},
        {"device_id":3,"address1":"2121 7th Ave","name1":"MG1","name2":"MG1 - 2 P4","lat":47.6164,"lon":-122.3387,"waitlist_allowed":true,"ports":[{"status_v2":"unavailable"},{"status_v2":"in_use"}]},
        {"device_id":9,"address1":"2250 7th Ave","name1":"MG2","name2":"MG2 - 1 P1","lat":47.6164,"lon":-122.3387,"waitlist_allowed":true,"ports":[{"status_v2":"available"}]}
        ]}}
        """
        let viaOwned = try cpOwnedStations(raw)   // the strict gate must accept the real shape
        XCTAssertEqual(viaOwned.map(\.deviceId), [1, 2, 3, 9])
        let stations = cpStationsFrom(raw)
        XCTAssertEqual(stations.map(\.free), [1, 2, 0, 1])
        XCTAssertEqual(stations.map(\.inUse), [1, 0, 1, 0])
        XCTAssertEqual(stations.map(\.offline), [0, 0, 1, 0])
    }

    func testEmptyStationListIsAcceptedNotAFailure() throws {
        XCTAssertEqual(try cpOwnedStations("{\"map_data\":{\"stations\":[]}}").count, 0)
        XCTAssertEqual(cpStationsFrom("{\"map_data\":{\"stations\":[]}}").count, 0)
    }

    // MARK: - A parse failure identifies itself (pure describer)

    func testDescriberClassifiesBodyShape() {
        XCTAssertEqual(cpParseFaultDetail(request: .status, body: ""), "empty body")
        XCTAssertEqual(cpParseFaultDetail(request: .status, body: "   \n "), "empty body")
        XCTAssertEqual(cpParseFaultDetail(request: .status, body: "<html><body>Access Denied</body></html>"),
                       "HTML page (39 bytes)")
        XCTAssertEqual(cpParseFaultDetail(request: .status, body: "nope not json"), "not JSON (13 bytes)")
        XCTAssertEqual(cpParseFaultDetail(request: .status, body: "[1,2,3]"), "top-level array, expected object")
    }

    func testDescriberNamesKeyPathAndExpectedVersusFoundType() {
        XCTAssertEqual(cpParseFaultDetail(request: .status, body: "{\"other\":1}"),
                       "user_status: expected object, absent")
        XCTAssertEqual(cpParseFaultDetail(request: .status, body: "{\"user_status\":{\"waitlist\":42}}"),
                       "user_status.waitlist: expected object, number")
        XCTAssertEqual(cpParseFaultDetail(request: .status,
            body: "{\"user_status\":{\"charging\":{\"state\":\"CHARGING\",\"sessionId\":\"x\"}}}"),
                       "user_status.charging.sessionId: expected integer, string")
        XCTAssertEqual(cpParseFaultDetail(request: .stationList,
            body: "{\"map_data\":{\"stations\":[{\"lat\":1,\"lon\":1}]}}"),
                       "map_data.stations[0].device_id: expected integer, absent")
    }

    func testDescriberNeverLeaksAValue() {
        // A token/email/id in the body must never appear in the structural description.
        let body = "{\"user_status\":{\"waitlist\":\"SECRET-TOKEN-abc@example.com-999\"}}"
        let detail = cpParseFaultDetail(request: .status, body: body)
        XCTAssertFalse(detail.contains("SECRET"))
        XCTAssertFalse(detail.contains("example.com"))
        XCTAssertEqual(detail, "user_status.waitlist: expected object, string")
    }

    // MARK: - Runtime: an idle account now reads, and a parse failure records host/status/request

    private func configured() throws -> (CpStateStore, URL) {
        let directory = try CpStoreFixture.directory(self)
        let store = CpStateStore(directory: directory)
        _ = try store.bootstrap(legacy: CpLegacyState(session: CpStoreFixture.session,
            location: CpStoreFixture.location, runWire: "0|0|0|7|0|||"), now: CpStoreFixture.now)
        return (store, directory)
    }

    func testIdleAccountReadsAndShowsPlugsInsteadOfCouldntRead() async throws {
        let (store, directory) = try configured()
        let instant = CpStoreFixture.now
        let stations = """
        {"map_data":{"stations":[
        {"device_id":1,"address1":"A","name1":"","name2":"SEA - 1 P2","lat":0.5,"lon":0.5,"waitlist_allowed":true,"ports":[{"status_v2":"available"},{"status_v2":"in_use"}]},
        {"device_id":2,"address1":"A","name1":"","name2":"SEA - 2 P2","lat":0.5,"lon":0.5,"waitlist_allowed":true,"ports":[{"status_v2":"available"}]}
        ]}}
        """
        let runtime = CpOwnedRuntime(store: store, directory: directory,
            transport: CpRoutingTransport(status: "{\"user_status\":{}}", stations: stations), now: { instant })
        let display = try await runtime.refresh(runAuto: false)
        XCTAssertNil(try store.snapshot(now: instant).failure, "an idle reply must not be a failure")
        XCTAssertFalse(display.stale)
        XCTAssertEqual(display.plugsFree, "2 of 3 free")
    }

    func testParseFailureRecordsRequestHostAndReceivedStatus() async throws {
        let (store, directory) = try configured()
        let instant = CpStoreFixture.now
        // A 200 whose user-status body is structurally wrong (waitlist is a number).
        let runtime = CpOwnedRuntime(store: store, directory: directory,
            transport: CpRoutingTransport(status: "{\"user_status\":{\"waitlist\":42}}"), now: { instant })
        _ = try await runtime.refresh(runAuto: false)
        let failure = try XCTUnwrap(try store.snapshot(now: instant).failure)
        XCTAssertEqual(failure.kind, .parse)
        XCTAssertEqual(failure.host, "mc.chargepoint.com")
        XCTAssertEqual(failure.status, 200, "the received HTTP status must survive a parse failure")
        XCTAssertEqual(failure.request, "status")
        XCTAssertEqual(failure.detail, "user_status.waitlist: expected object, number")
    }

    func testDiagnosticsTextShowsRequestAndStructuralDetailForParseFailure() {
        let attempt = CpDiagnosticsAttempt(at: "8:08 PM", host: "mc.chargepoint.com", status: 200,
            reason: "Couldn't read ChargePoint's reply", request: "status",
            detail: "user_status.waitlist: expected object, number")
        let text = cpDiagnosticsText(CpDiagnosticsInput(tokenPresent: true, userIDPresent: true,
            expired: false, minutesLeft: nil, lastAttempt: attempt, appVersion: "1.0", build: "19"))
        XCTAssertTrue(text.contains("Host: mc.chargepoint.com"))
        XCTAssertTrue(text.contains("HTTP status: 200"))
        XCTAssertTrue(text.contains("Request: status"))
        XCTAssertTrue(text.contains("Detail: user_status.waitlist: expected object, number"))
    }
}

// MARK: - Transport that routes map-prod/v2 by request body (status vs stations)

private final class CpRoutingTransport: CpOwnedTransport, @unchecked Sendable {
    private let status: String
    private let stations: String
    private let code: Int
    init(status: String, stations: String = "{\"map_data\":{\"stations\":[]}}", code: Int = 200) {
        self.status = status; self.stations = stations; self.code = code
    }
    func prepare(_ request: URLRequest) throws -> any CpPreparedRequest {
        let body = request.httpBody.flatMap { String(data: $0, encoding: .utf8) } ?? ""
        let reply = body.contains("user_status") ? status : (body.contains("map_data") ? stations : "{}")
        return CpReplyPrepared(url: request.url!, body: reply, code: code)
    }
}

private struct CpReplyPrepared: CpPreparedRequest {
    let url: URL
    let body: String
    let code: Int
    func start() {}
    func cancel() {}
    func response() async throws -> (Data, HTTPURLResponse) {
        (Data(body.utf8), HTTPURLResponse(url: url, statusCode: code, httpVersion: nil, headerFields: nil)!)
    }
}
