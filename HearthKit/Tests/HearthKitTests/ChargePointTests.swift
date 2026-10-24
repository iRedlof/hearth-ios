import XCTest
@testable import HearthKit

final class ChargePointTests: XCTestCase {
    // The map reply from ChargePointStateTest.kt (4 stations at two addresses).
    private let mapJSON = """
    {"map_data":{"stations":[
      {"device_id":1,"address1":"2121 7th Ave","name1":"SEA41","name2":"SEA41 - 1 P3","lat":47.6164,"lon":-122.3387,"waitlist_allowed":true,"ports":[{"status_v2":"available"},{"status_v2":"in_use"}]},
      {"device_id":2,"address1":"2121 7th Ave","name1":"SEA41","name2":"SEA41-15 P3","lat":47.6164,"lon":-122.3387,"waitlist_allowed":true,"ports":[{"status_v2":"available"},{"status_v2":"available"}]},
      {"device_id":3,"address1":"2121 7th Ave","name1":"SEA41","name2":"SEA41 - 2 P4","lat":47.6164,"lon":-122.3387,"waitlist_allowed":true,"ports":[{"status_v2":"unavailable"},{"status_v2":"in_use"}]},
      {"device_id":9,"address1":"2250 7th Ave","name1":"SEA43","name2":"SEA43 - 1 P1","lat":47.6164,"lon":-122.3387,"waitlist_allowed":true,"ports":[{"status_v2":"available"}]}
    ],"waitlist":{"state":"NOT_QUEUED"}}}
    """

    func testStationsPortsCounted() {
        let s = cpStationsFrom(mapJSON)
        XCTAssertEqual(s.count, 4)
        XCTAssertEqual(s.map { $0.free }, [1, 2, 0, 1])
        XCTAssertEqual(s.map { $0.inUse }, [1, 0, 1, 0])
        XCTAssertEqual(s.map { $0.offline }, [0, 0, 1, 0])
    }

    func testLocationsGroupedByAddressBiggestFirst() {
        let l = cpLocations(cpStationsFrom(mapJSON))
        XCTAssertEqual(l.map { $0.address }, ["2121 7th Ave", "2250 7th Ave"])
        XCTAssertEqual(l.first?.deviceIds, [1, 2, 3])
        XCTAssertEqual(l.first?.name, "SEA41")
    }

    func testLocationNowOwnStationsOnly() {
        let stations = cpStationsFrom(mapJSON)
        let loc = cpLocations(stations).first!
        XCTAssertEqual(cpLocationNow(loc, stations), CpNow(free: 3, inUse: 2, offline: 1, stations: 3))
    }

    func testChargerIdIsNotASite() {
        let json = """
        {"map_data":{"stations":[
          {"device_id":5,"address1":"925 4th Avenue","name1":"BAE818124","name2":"BAE818124","lat":47.6,"lon":-122.3,"waitlist_allowed":true,"ports":[{"status_v2":"available"}]},
          {"device_id":6,"address1":"925 4th Avenue","name1":"BAE818129","name2":"BAE818129","lat":47.6,"lon":-122.3,"waitlist_allowed":true,"ports":[{"status_v2":"available"}]}
        ],"waitlist":{"state":"NOT_QUEUED"}}}
        """
        let l = cpLocations(cpStationsFrom(json))
        XCTAssertEqual(l.map { $0.name }, ["925 4th Avenue"])
        XCTAssertEqual(l.first?.deviceIds, [5, 6])
    }

    func testWaitlistState() {
        let empty = """
        {"user_status":{}}
        """
        let waiting = """
        {"user_status":{"waitlist":{"state":{"state":"WAITING","regionId":0},"stations":[{"deviceId":13104611},{"deviceId":2}]}}}
        """
        let inline = """
        {"positionInline":1,"joinDate":1792368043000}
        """
        XCTAssertEqual(cpWaitlistFrom(empty, nil), .notQueued)
        XCTAssertEqual(cpWaitlistFrom(waiting, inline),
                       .inLine(place: 1, state: "WAITING", stations: 2, offer: nil, auto: false))
        XCTAssertEqual(cpWaitlistFrom(waiting, nil),
                       .inLine(place: nil, state: "WAITING", stations: 2, offer: nil, auto: false))
    }

    private let offered = """
    {"user_status":{"waitlist":{"state":{"state":"ACCEPT_PENDING","regionId":0,"currentTimeUTC":1792372115,"startTimeUTC":1792372024,"deviceId":16235001,"duration":1200,"token":"T0K3N","portNo":1},"stations":[{"deviceId":13104611,"name":"SEA41 SEA41-7 P2"},{"deviceId":16235001,"name":"SEA41 SEA41-29 P3"}]}}}
    """

    func testOfferAndToken() {
        guard case let .inLine(_, state, _, offer, _) = cpWaitlistFrom(offered, nil) else { return XCTFail("expected inLine") }
        XCTAssertEqual(state, "ACCEPT_PENDING")
        XCTAssertEqual(offer, CpOffer(deviceId: 16235001, port: 1, charger: "SEA41-29 P3",
                                      untilMs: (1792372024 + 1200) * 1000, startMs: 1792372024 * 1000))
        XCTAssertEqual(cpOfferToken(offered), "T0K3N")
        let waitingNoToken = """
        {"user_status":{"waitlist":{"state":{"state":"WAITING"},"stations":[]}}}
        """
        XCTAssertNil(cpOfferToken(waitingNoToken))
    }

    func testWaitingHasNoOffer() {
        let waiting = """
        {"user_status":{"waitlist":{"state":{"state":"WAITING"},"stations":[{"deviceId":1}]}}}
        """
        guard case let .inLine(_, _, _, offer, _) = cpWaitlistFrom(waiting, nil) else { return XCTFail("expected inLine") }
        XCTAssertNil(offer)
    }

    func testAutoSnoozeToldApart() {
        let auto = """
        {"user_status":{"waitlist":{"state":{"state":"PASS","startTimeUTC":1792373255,"duration":1800,"autoSnooze":true},"stations":[]}}}
        """
        guard case let .inLine(_, _, _, offer, isAuto) = cpWaitlistFrom(auto, nil) else { return XCTFail("expected inLine") }
        XCTAssertTrue(isAuto)
        XCTAssertEqual(offer?.startMs, 1792373255000)
    }

    func testSessionId() {
        let charging = """
        {"user_status":{"charging":{"sessionId":42,"state":"CHARGING","startTimeUTC":1}}}
        """
        let empty = """
        {"user_status":{}}
        """
        XCTAssertEqual(cpSessionId(charging), 42)
        XCTAssertNil(cpSessionId(empty))
    }

    func testFinishedSessionIsNotLive() {
        let done = """
        {"user_status":{"charging":{"sessionId":5633159011,"state":"fully_charged"}}}
        """
        let live = """
        {"user_status":{"charging":{"sessionId":5633159011,"state":"in_use"}}}
        """
        XCTAssertNil(cpSessionId(done))
        XCTAssertEqual(cpSessionId(live), 5633159011)
    }

    func testChargingNumbers() {
        let d = """
        {"charging_status":{"session_id":42,"power_kw":6.62,"energy_kwh":7.41,"charging_time":3900000,"stop_charge_supported":true,"enable_stop_charging":true}}
        """
        let c = cpChargingFrom(d)
        XCTAssertEqual(c?.sessionId, 42)
        XCTAssertEqual(c?.powerKw ?? 0, 6.62, accuracy: 0.001)
        XCTAssertEqual(c?.energyKwh ?? 0, 7.41, accuracy: 0.001)
        XCTAssertEqual(c?.minutes, 65)
        XCTAssertEqual(c?.seconds, 3900)
        XCTAssertEqual(c?.canStop, true)
        let noStop = """
        {"charging_status":{"session_id":42,"power_kw":0,"stop_charge_supported":false}}
        """
        XCTAssertEqual(cpChargingFrom(noStop)?.canStop, false)
    }

    func testAccountRow() {
        XCTAssertEqual(cpAccount(hasSession: true, expired: false),
                       CpAccount(text: "Signed in · Join & charging expire ~2h after sign-in", signedIn: true))
        XCTAssertEqual(cpAccount(hasSession: true, expired: true),
                       CpAccount(text: "Signed out by ChargePoint: sign in again", signedIn: false))
        XCTAssertEqual(cpAccount(hasSession: false, expired: false),
                       CpAccount(text: "Not signed in: ChargePoint's own login page", signedIn: false))
        XCTAssertTrue(cpAccount(hasSession: true, expired: false, joinExpired: true).needsReauth)
    }

    func testBrandToneIsOrange() {
        XCTAssertEqual(BeaconTone.orange.fillARGB, 0xFFF68A2B)
        XCTAssertEqual(BeaconTone.orange.inkARGB, 0xFF2C210F)
    }
}
