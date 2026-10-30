import Foundation

/// Pending feedback is persisted independently of the device's actual reported state.
public struct AlarmOperation: Codable, Sendable, Equatable {
    public var id: String
    public var entityID: String
    public var action: String
    public var startedAt: Date
    public var error: String?
    public var pending: Bool { error == nil }
    public init(entityID: String, action: String, startedAt: Date, id: String = UUID().uuidString,
                error: String? = nil) {
        self.id = id; self.entityID = entityID; self.action = action
        self.startedAt = startedAt; self.error = error
    }
}

public func alarmApplyingOperation(_ snapshot: AlarmSnapshot, _ operation: AlarmOperation?) -> AlarmSnapshot {
    guard let operation, operation.entityID == snapshot.entityID || operation.entityID == snapshot.lockID else { return snapshot }
    var result = snapshot
    result.commandPending = operation.pending
    result.commandError = operation.error
    if operation.pending {
        switch operation.action {
        case "armHome": result.commandFeedback = "Arming home…"
        case "armAway": result.commandFeedback = "Arming away…"
        case "disarm": result.commandFeedback = "Disarming…"
        case "lock": result.commandFeedback = "Locking door…"
        case "unlock": result.commandFeedback = "Unlocking door…"
        default: result.commandFeedback = "Updating…"
        }
        result.actions = []
        result.doorAction = nil
    } else {
        result.commandFeedback = "Couldn't confirm · Refresh to check"
    }
    return result
}
