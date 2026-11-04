import Foundation
import HearthKit

enum CpLiveSnapshot {
    static func fetch(now _: Date? = nil, advanceAuto: Bool = false) async -> CpSnapshot {
        do {
            // A dashboard display date must never freeze admission/lease time across network awaits.
            let runtime = try CpSessionStore.runtime()
            return try await runtime.refresh(runAuto: advanceAuto)
        } catch {
            return CpSessionStore.unavailableSnapshot
        }
    }

    static func fetchTimeline(advanceAuto: Bool = true) async -> [CpTimelineDisplay] {
        do {
            return try await CpSessionStore.runtime().refreshTimeline(runAuto: advanceAuto)
        } catch {
            return [CpTimelineDisplay(date: .now, snapshot: CpSessionStore.unavailableSnapshot)]
        }
    }
}
