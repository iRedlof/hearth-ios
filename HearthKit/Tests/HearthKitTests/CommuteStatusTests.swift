import Testing
import Foundation
@testable import HearthKit

@Suite("CommuteStatus Mapper")
struct CommuteStatusTests {
    let freshThreshold: TimeInterval = 300 // 5 minutes

    @Test("Fresh sensor returns found")
    func freshSensorFound() {
        let now = Date(timeIntervalSince1970: 1000)
        let lastHeard = Date(timeIntervalSince1970: 900) // 100s ago
        let status = commuteStatus(lastHeard: lastHeard, now: now, threshold: freshThreshold)
        #expect(status == .found)
    }

    @Test("Stale sensor returns lastHeard with date")
    func staleSensorLastHeard() {
        let now = Date(timeIntervalSince1970: 10000)
        let lastHeard = Date(timeIntervalSince1970: 1000) // 9000s ago
        let status = commuteStatus(lastHeard: lastHeard, now: now, threshold: freshThreshold)
        if case .lastHeard(let date) = status {
            #expect(date == lastHeard)
        } else {
            Issue.record("Expected lastHeard, got \(status)")
        }
    }

    @Test("Nil lastHeard returns waiting")
    func nilLastHeardWaiting() {
        let now = Date()
        let status = commuteStatus(lastHeard: nil, now: now, threshold: freshThreshold)
        #expect(status == .waiting)
    }

    @Test("Boundary at threshold - exactly at threshold is stale")
    func boundaryAtThreshold() {
        let now = Date(timeIntervalSince1970: 1000)
        let lastHeard = Date(timeIntervalSince1970: 1000 - freshThreshold) // exactly threshold ago
        let status = commuteStatus(lastHeard: lastHeard, now: now, threshold: freshThreshold)
        // At the boundary, we consider it stale (not fresh)
        if case .lastHeard(let date) = status {
            #expect(date == lastHeard)
        } else {
            Issue.record("Expected lastHeard at boundary, got \(status)")
        }
    }

    @Test("Just within threshold is fresh")
    func justWithinThreshold() {
        let now = Date(timeIntervalSince1970: 1000)
        let lastHeard = Date(timeIntervalSince1970: 1000 - freshThreshold + 1) // 1s within threshold
        let status = commuteStatus(lastHeard: lastHeard, now: now, threshold: freshThreshold)
        #expect(status == .found)
    }
}
