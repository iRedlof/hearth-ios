import Foundation

public struct ClimateCommand: Sendable, Equatable {
    public let domain: String
    public let service: String
    public let entityID: String
    public let temperatures: [String: Double]
    public let optionKey: String?
    public let option: String?
}

/// Validates both the displayed action and the latest device capabilities.
public func climateCommand(_ state: ClimateState, entityID: String, action: String,
                           resumeID: String = "", option: String? = nil) -> ClimateCommand? {
    guard entityID.hasPrefix("climate."), state.isAvailable else { return nil }
    switch action {
    case "heatUp", "heatDown", "coolUp", "coolDown":
        let side: ClimateSide = action.hasPrefix("heat") ? .heat : .cool
        guard let values = setpointNudge(state, side: side, by: action.hasSuffix("Up") ? 1 : -1) else { return nil }
        return ClimateCommand(domain: "climate", service: "set_temperature", entityID: entityID,
            temperatures: values, optionKey: nil, option: nil)
    case "resume":
        guard resumeID.hasPrefix("button.") else { return nil }
        return ClimateCommand(domain: "button", service: "press", entityID: resumeID,
            temperatures: [:], optionKey: nil, option: nil)
    case "mode", "fan":
        guard let option, climateOptions(state, kind: action).contains(option),
              option != (action == "fan" ? state.fanMode : state.mode) else { return nil }
        return ClimateCommand(domain: "climate", service: action == "fan" ? "set_fan_mode" : "set_hvac_mode",
            entityID: entityID, temperatures: [:], optionKey: action == "fan" ? "fan_mode" : "hvac_mode", option: option)
    default: return nil
    }
}

/// A scope change during the live read invalidates a command before dispatch.
@discardableResult
public func executeClimateAction(entityID: String, action: String, resumeID: String = "", option: String? = nil,
                                 expectedMode: String? = nil,
                                 isCurrent: @Sendable () -> Bool,
                                 read: @Sendable () async throws -> ClimateState?,
                                 send: @Sendable (ClimateCommand) async throws -> Void) async throws -> Bool {
    guard ["heatUp", "heatDown", "coolUp", "coolDown", "resume", "mode", "fan"].contains(action),
          isCurrent() else { return false }
    try Task.checkCancellation()
    guard let state = try await read(), isCurrent() else { return false }
    if ["heatUp", "heatDown", "coolUp", "coolDown"].contains(action),
       let expectedMode, state.mode != expectedMode { return false }
    guard
          let command = climateCommand(state, entityID: entityID, action: action, resumeID: resumeID, option: option) else {
        return false
    }
    try Task.checkCancellation()
    guard isCurrent() else { return false }
    try await send(command)
    return true
}
