import Foundation
import Testing
@testable import HearthKit

/// The garage is read in the Alarm card's own refresh, beside the panel and the front door.
@Suite("Alarm garage fetch")
struct AlarmGarageFetchTests {
    private final class Requests: @unchecked Sendable {
        private let lock = NSLock()
        private var ids: [String] = []
        func record(_ id: String) { lock.lock(); ids.append(id); lock.unlock() }
        var sorted: [String] { lock.lock(); defer { lock.unlock() }; return ids.sorted() }
    }

    private static let now = Date(timeIntervalSince1970: 1_792_601_160)
    private static let panel = #"{"entity_id":"alarm_control_panel.home","state":"disarmed","attributes":{"friendly_name":"Home Alarm","supported_features":3}}"#
    private static let lock = #"{"entity_id":"lock.front","state":"locked","attributes":{"friendly_name":"Front Door"}}"#
    private static let garage = #"{"entity_id":"cover.garage","state":"closed","attributes":{"friendly_name":"Garage","device_class":"garage","supported_features":11}}"#
    private static let blind = #"{"entity_id":"cover.garage","state":"closed","attributes":{"friendly_name":"Blind","device_class":"blind"}}"#

    private static func config(garage: String? = "cover.garage") -> HaConfig {
        HaConfig(baseUrl: "https://example.invalid", token: "inert", entityId: "alarm_control_panel.home",
                 lockId: "lock.front", lockName: "Front Door", garageId: garage)
    }
    private static func reply(_ id: String, garage: String = garage) -> String {
        id.hasPrefix("cover.") ? garage : id.hasPrefix("lock.") ? lock : panel
    }

    @Test("Panel, front door and garage are read once each in one fetch")
    func oneFetchReadsAllThree() async throws {
        let requests = Requests()
        let result = await fetchAlarmReadings(Self.config(), now: Self.now) { id in
            requests.record(id)
            return Self.reply(id)
        }
        #expect(requests.sorted == ["alarm_control_panel.home", "cover.garage", "lock.front"])
        #expect(result.errors.isEmpty)
        let snapshot = result.snapshot(now: Self.now)
        let garage = try #require(snapshot.garage)
        #expect(garage.name == "Garage")
        #expect(garage.state == "Closed")
        #expect(garage.action == .open)
        #expect(snapshot.doorAction == .unlock)
        #expect(snapshot.actions == [.armHome, .armAway])
    }

    @Test("With no garage chosen the cover is never requested")
    func noGarageNoRequest() async {
        let requests = Requests()
        let result = await fetchAlarmReadings(Self.config(garage: ""), now: Self.now) { id in
            requests.record(id)
            return Self.reply(id)
        }
        #expect(requests.sorted == ["alarm_control_panel.home", "lock.front"])
        #expect(result.snapshot(now: Self.now).garage == nil)
    }

    @Test("A reply that is not this garage fails the garage only")
    func wrongGarageReplyIsIsolated() async throws {
        let result = await fetchAlarmReadings(Self.config(), now: Self.now) { id in Self.reply(id, garage: Self.blind) }
        #expect(result.errors["cover.garage"] != nil)
        #expect(result.readings["cover.garage"] == nil)
        let snapshot = result.snapshot(now: Self.now)
        let garage = try #require(snapshot.garage)
        #expect(garage.state == "Unavailable")
        #expect(garage.action == nil)
        #expect(snapshot.doorAction == .unlock)
        #expect(snapshot.error == nil)
    }

    @Test("A failed garage read keeps its own last reading and time")
    func failedGarageKeepsItsOwnHistory() async throws {
        let old = HaStateReading(entityID: "cover.garage", json: Self.garage, checkedAt: Self.now.addingTimeInterval(-600))
        let result = await fetchAlarmReadings(Self.config(), previous: ["cover.garage": old], now: Self.now) { id in
            if id.hasPrefix("cover.") { throw HaError("Can't reach Home Assistant") }
            return Self.reply(id)
        }
        #expect(result.readings["cover.garage"]?.checkedAt == old.checkedAt)
        #expect(result.readings["lock.front"]?.checkedAt == Self.now)
        let snapshot = result.snapshot(now: Self.now)
        let garage = try #require(snapshot.garage)
        #expect(garage.stale)
        #expect(garage.state == "Closed")
        #expect(garage.action == nil)
        #expect(!snapshot.doorStale)
    }
}
