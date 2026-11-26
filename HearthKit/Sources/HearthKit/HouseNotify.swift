import Foundation

/// A notification to be scheduled at a specific time
public struct PlannedNotification: Sendable, Equatable {
    public let id: String
    public let title: String
    public let body: String
    public let fireAt: Date

    public init(id: String, title: String, body: String, fireAt: Date) {
        self.id = id
        self.title = title
        self.body = body
        self.fireAt = fireAt
    }
}

/// Compute the list of notifications to schedule for leave-by checks and travel trips.
///
/// IDs are stable — the same event title produces the same id across runs, so rescheduling
/// replaces rather than duplicates. If multiple items share the same id (duplicate event titles),
/// only the first is included.
///
/// - Parameters:
///   - leaveBy: Leave-by checks (pre-departure house checks)
///   - travel: Travel trips (vacation-mode offers)
/// - Returns: Planned notifications sorted by fireAt ascending, deduplicated by id
public func plannedNotifications(
    leaveBy: [LeaveByCheck],
    travel: [Trip]
) -> [PlannedNotification] {
    var seen: Set<String> = []
    var notifications: [PlannedNotification] = []

    // Leave-by checks
    for check in leaveBy {
        let id = "leaveby-\(slug(check.eventTitle))"
        guard !seen.contains(id) else {
            continue
        }
        seen.insert(id)

        let itemsDesc = check.items.map { item in
            switch item {
            case .alarm: return "alarm"
            case .lock: return "locks"
            case .thermostat: return "thermostat"
            }
        }.joined(separator: ", ")

        let title = "Before leaving for \(check.eventTitle)"
        let body = "Check: \(itemsDesc)"

        notifications.append(PlannedNotification(
            id: id,
            title: title,
            body: body,
            fireAt: check.notifyAt
        ))
    }

    // Travel trips
    for trip in travel {
        let id = "travel-\(slug(trip.title))"
        guard !seen.contains(id) else {
            continue
        }
        seen.insert(id)

        let title = "Trip tomorrow: \(trip.title)"
        let body = "Enable vacation mode?"

        notifications.append(PlannedNotification(
            id: id,
            title: title,
            body: body,
            fireAt: trip.notifyAt
        ))
    }

    // Sort by fireAt ascending
    return notifications.sorted { $0.fireAt < $1.fireAt }
}

/// Convert a string to a stable slug for use in notification ids.
///
/// Lowercase, spaces → dashes, strip non-ASCII alphanumeric except dashes.
private func slug(_ s: String) -> String {
    let lower = s.lowercased()
    let dashed = lower.replacingOccurrences(of: " ", with: "-")
    let cleaned = dashed.filter { ch in
        (ch >= "a" && ch <= "z") || (ch >= "0" && ch <= "9") || ch == "-"
    }
    return String(cleaned)
}
