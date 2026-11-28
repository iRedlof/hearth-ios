#if DEBUG
import Foundation
import HearthKit

/// Seeds the production ChargePoint store (App Group) with a signed-in, located, Auto-on account so
/// the ChargePoint page, alerts page and ChargePoint widget read "connected". Installs a canned
/// transport (via CpSessionStore's DEBUG seam) so `CpLiveSnapshot.fetch`/`runtime.refresh` commit a
/// real reading: the ChargePoint widget status line and Home card hero show availability instead of
/// "stale"/"Couldn't check". DEBUG only.
enum DemoHouseChargePoint {
    static func seed() {
        do {
            let directory = try CpSessionStore.directory()
            // Deterministic reseed: clear any prior demo/real state so bootstrap re-imports cleanly.
            if FileManager.default.fileExists(atPath: directory.path) {
                try FileManager.default.removeItem(at: directory)
            }
            let store = CpStateStore(directory: directory)
            let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
            let run = CpRun(armed: true, startedAt: Int64(Date().timeIntervalSince1970))
            let location = CpLocation(name: "Rivergate Garage", address: "1 Demo Street",
                                      deviceIds: [1, 2, 3, 4, 5], bounds: cpBounds(lat: 47.62, lon: -122.34))
            _ = try store.bootstrap(legacy: CpLegacyState(
                session: CpSession(token: "demo-cp-cookie", userId: 4242, email: "demo@example.com",
                                   renewedAt: nowMs),
                location: location,
                runWire: cpRunToWire(run),
                alerts: CpAlertPrefs(offer: true, accepted: true, snoozed: true, second: true),
                udid: "demo-house-device"))
            CpSessionStore.demoTransportProvider = { DemoCpTransport() }
        } catch {
            NSLog("[DemoHouse] ChargePoint seed failed: \(error)")
        }
    }
}

/// A canned ChargePoint transport. Answers the owned pipeline's status/stations calls with a calm,
/// populated idle station (not queued, availability shown) and mutations with success. Modelled on the
/// native ownership fixture's transport. DEBUG only.
final class DemoCpTransport: CpOwnedTransport, @unchecked Sendable {
    func prepare(_ request: URLRequest) throws -> any CpPreparedRequest {
        guard let url = request.url else { throw URLError(.badURL) }
        let path = url.path
        let object = request.httpBody.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
        let mutation = path.hasSuffix("/join") || path.hasSuffix("/snoozeV2") || path.hasSuffix("/acceptV2")
            || path.hasSuffix("/leave") || path.hasSuffix("/unsnoozeV2")
        let body: String
        if mutation { body = #"{"result":true,"response":{"success":true}}"# }
        else if object?["user_status"] != nil { body = Self.statusJSON }
        else if object?["map_data"] != nil { body = Self.stationsJSON }
        else if path.hasSuffix("/inlinestatus") { body = #"{"positionInline":0}"# }
        else if path.contains("/get_notification_detail/") { body = #"{"response":{"remainingSnoozeCount":2}}"# }
        else { body = "{}" }
        return DemoCpPrepared(url: url, body: body)
    }

    /// Signed-in, idle (not in any waitlist). Availability comes from the stations call below.
    private static let statusJSON = #"{"user_status":{"waitlist":{"state":{"state":"NOT_QUEUED"},"stations":[]}}}"#

    /// Five stations matching the seeded location device IDs, spread across floors P2–P6, mostly free.
    private static let stationsJSON: String = {
        let floors = ["P2", "P3", "P4", "P5", "P6"]
        let ports: [[String]] = [
            ["available", "available", "in_use"],
            ["available", "available", "available", "available"],
            ["available", "available", "available"],
            ["available", "in_use", "available", "available"],
            ["available", "available", "offline"]
        ]
        let stations: [[String: Any]] = (0..<5).map { i in station(index: i, floor: floors[i], ports: ports[i]) }
        let root: [String: Any] = ["map_data": ["stations": stations]]
        let data = (try? JSONSerialization.data(withJSONObject: root)) ?? Data("{}".utf8)
        return String(decoding: data, as: UTF8.self)
    }()

    private static func station(index: Int, floor: String, ports: [String]) -> [String: Any] {
        let portObjects: [[String: Any]] = ports.map { ["status_v2": $0] }
        var station: [String: Any] = [:]
        station["device_id"] = index + 1
        station["lat"] = 47.62 + Double(index) * 0.0001
        station["lon"] = -122.34 - Double(index) * 0.0001
        station["name1"] = "Rivergate Garage"
        station["name2"] = "\(floor) - \(index + 1)"
        station["parking_label"] = floor
        station["address1"] = "1 Demo Street"
        station["city"] = "Seattle"
        station["state_name"] = "WA"
        station["waitlist_allowed"] = true
        station["ports"] = portObjects
        return station
    }
}

private struct DemoCpPrepared: CpPreparedRequest {
    let url: URL
    let body: String
    func start() {}
    func cancel() {}
    func response() async throws -> (Data, HTTPURLResponse) {
        (Data(body.utf8), HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!)
    }
}
#endif
