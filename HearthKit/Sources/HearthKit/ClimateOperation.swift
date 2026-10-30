import Foundation

/// Command feedback is separate from telemetry: service acknowledgement is not a temperature reading.
public struct ClimateOperation: Codable, Sendable, Equatable {
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

public func climateApplyingOperation(_ snapshot: ThermostatSnapshot, _ operation: ClimateOperation?) -> ThermostatSnapshot {
    guard let operation else { return snapshot }
    var result = snapshot
    result.commandPending = operation.pending
    result.commandError = operation.error
    if operation.pending {
        switch operation.action {
        case "heatUp", "heatDown": result.commandFeedback = "Updating heat…"
        case "coolUp", "coolDown": result.commandFeedback = "Updating cool…"
        case "mode": result.commandFeedback = "Updating mode…"
        case "fan": result.commandFeedback = "Updating fan…"
        case "resume": result.commandFeedback = "Resuming schedule…"
        default: result.commandFeedback = "Updating…"
        }
        result.canAdjustHeatUp = false; result.canAdjustHeatDown = false
        result.canAdjustCoolUp = false; result.canAdjustCoolDown = false
        result.canPickMode = false; result.canPickFan = false; result.canResume = false
    } else {
        result.commandFeedback = "Update failed · Try again"
    }
    return result
}
