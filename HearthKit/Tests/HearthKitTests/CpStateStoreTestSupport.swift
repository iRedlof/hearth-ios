import Foundation
import XCTest
@testable import HearthKit

enum CpStoreFixture {
    static let now = Date(timeIntervalSince1970: 1_000)
    static let session = CpSession(token: "inert-fixture-cookie", userId: 17, email: "person@example.invalid",
                                   renewedAt: 900_000)
    static let location = CpLocation(name: "Amazon Day 1", address: "Fixture address",
        deviceIds: [1, 2], bounds: CpBounds(swLat: 0, swLon: 0, neLat: 1, neLon: 1), label: "Office")
    static let otherLocation = CpLocation(name: "Other", address: "Other fixture",
        deviceIds: [3], bounds: CpBounds(swLat: 2, swLon: 2, neLat: 3, neLon: 3))
    static let runWire = "1|1|1|7|1|ACCEPT_PENDING|9000|Saved failure"
    static let run = CpRun(armed: true, snoozeUsed: true, drivePushed: true, startedAt: 7,
                           offerPushed: true, failedState: "ACCEPT_PENDING", failedUntil: 9_000,
                           failedReason: "Saved failure")
    static let alerts = CpAlertPrefs(offer: false, accepted: true, snoozed: false, second: true)
    static let udid = "inert-fixture-device"
    static var legacy: CpLegacyState {
        CpLegacyState(session: session, location: location, runWire: runWire, alerts: alerts, udid: udid)
    }

    static func directory(_ test: XCTestCase) throws -> URL {
        let value = FileManager.default.temporaryDirectory.appendingPathComponent("cp-state-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: value, withIntermediateDirectories: true)
        test.addTeardownBlock { try? FileManager.default.removeItem(at: value) }
        return value
    }

    static func reading(_ place: Int) -> CpProviderReading {
        CpProviderReading(waitlist: .inLine(place: place, state: "WAITING", stations: 43, offer: nil, auto: false))
    }
}
