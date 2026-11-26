import Foundation

public struct ThermostatSensor: Sendable, Equatable {
    public var name: String
    public var value: String
    public var id: String
    public var stale: Bool
    public init(name: String, value: String, id: String? = nil, stale: Bool = false) {
        self.name = name; self.value = value; self.id = id ?? name; self.stale = stale
    }
}

/// Everything the Thermostat Beacon view renders, already formatted (mirrors CarSnapshot/AlarmSnapshot).
public struct ThermostatSnapshot: Sendable, Equatable {
    public var name: String            // "Thermostat"
    public var checkedAt: String       // "9:41 AM"
    public var roomTemp: String        // "71°"
    public var roomSub: String         // "In the room"
    public var humidity: String?       // "52% humidity"
    public var status: String          // the climateViewFor headline: "Cooling to 70°" / "Holding 64–70°"
    public var tone: BeaconTone
    public var heatSetpoint: String?   // "64°" (nil when the mode has no heat target)
    public var coolSetpoint: String?   // "70°"
    public var mode: String            // "Heat" / "Cool" / "Auto" / "Off" / "Fan" / "Dry"
    public var fan: String?            // "Auto" / "On"
    public var canResume: Bool
    public var sensors: [ThermostatSensor]
    public var setup: Bool = false
    public var stale: Bool = false
    public var error: String?
    public var needsSettings: Bool = false
    public var needsSignIn: Bool = false
    public var canAdjustHeatUp: Bool = false
    public var canAdjustHeatDown: Bool = false
    public var canAdjustCoolUp: Bool = false
    public var canAdjustCoolDown: Bool = false
    public var canPickMode: Bool = false
    public var canPickFan: Bool = false
    public var hasFanControl: Bool = false
    public var hasResumeControl: Bool = false
    public var entityID: String = ""
    public var resumeID: String = ""
    public var requestScope: String = ""
    public var climateRevision: String = ""
    public var commandPending: Bool = false
    public var commandFeedback: String?
    public var commandError: String?
    /// Raw opening evidence survives snapshot-only publication without reconstructing its origin.
    public var evidence: ThermostatRawEvidence?

    public init(name: String, checkedAt: String, roomTemp: String, roomSub: String, humidity: String?,
                status: String, tone: BeaconTone, heatSetpoint: String?, coolSetpoint: String?,
                mode: String, fan: String?, canResume: Bool, sensors: [ThermostatSensor]) {
        self.name = name; self.checkedAt = checkedAt; self.roomTemp = roomTemp; self.roomSub = roomSub
        self.humidity = humidity; self.status = status; self.tone = tone; self.heatSetpoint = heatSetpoint
        self.coolSetpoint = coolSetpoint; self.mode = mode; self.fan = fan; self.canResume = canResume
        self.hasFanControl = fan != nil; self.hasResumeControl = canResume
        self.sensors = sensors
    }

    public static let sample = ThermostatSnapshot(
        name: "Thermostat", checkedAt: "9:41 AM", roomTemp: "71°", roomSub: "In the room",
        humidity: "52% humidity", status: "Holding 64–70°", tone: .violet,
        heatSetpoint: "64°", coolSetpoint: "70°", mode: "Auto", fan: "Auto", canResume: true,
        sensors: [ThermostatSensor(name: "Outside", value: "44°"),
                  ThermostatSensor(name: "Bedroom", value: "72°"),
                  ThermostatSensor(name: "Thermo", value: "72°")])
}
