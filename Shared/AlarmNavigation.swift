import Foundation
import HearthKit

/// Immutable snapshots share a bounded local store; a URL carries only one opaque ticket ID.
enum AlarmReadingsStore {
    static var store: AlarmReadingsTicketStore? {
        guard let container = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: HaConfigStore.appGroup) else { return nil }
        return AlarmReadingsTicketStore(directory:
            container.appendingPathComponent("Library/Application Support/AlarmReadings"))
    }
    static func bind(_ snapshot: AlarmSnapshot, date: Date = .now) -> AlarmReadingsEntryPayload {
        // A real unreadable store must expose recovery, whereas explicit examples remain inert.
        if snapshot.storageUnavailable {
            return AlarmReadingsEntryPayload(date: date, snapshot: snapshot, destination: .unavailable)
        }
        return bindAlarmReadingsEntry(snapshot, date: date) { ticket in
            guard let store else { throw HaError("Shared storage is unavailable") }
            try store.save(ticket, now: date)
        }
    }
}
