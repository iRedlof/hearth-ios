import Foundation

/// The car as Home Assistant last heard from it; nil readings are ones it doesn't know.
/// Ported from Android `CarState.kt` (`data class Car`, 30 fields).
public struct Car: Sendable, Equatable {
    public var name: String
    public var battery: Int?
    public var range: Int?
    public var unit: String
    public var chargeState: String?
    public var plugged: Bool
    public var chargerKw: Double?
    public var fullAt: Date?
    public var limit: Int?
    public var locked: Bool?
    public var open: [String]
    public var tireWarning: Bool
    public var sentry: Bool
    public var place: String?
    public var inside: Int?
    public var tempUnit: String
    public var awake: Bool?
    public var since: Date?
    public var tires: [Int]?
    public var pressureUnit: String
    public var outside: Int?
    public var odometer: Int?
    public var addedKwh: Double?
    public var climateOn: Bool?
    public var sentryKnown: Bool
    public var pluggedKnown: Bool
    public var openKnown: Bool
    public var preciseTires: [Double]?
    public var preciseInside: Double?
    public var preciseOutside: Double?

    public init(name: String, battery: Int?, range: Int?, unit: String, chargeState: String?,
                plugged: Bool, chargerKw: Double?, fullAt: Date?, limit: Int?, locked: Bool?,
                open: [String], tireWarning: Bool, sentry: Bool, place: String?, inside: Int?,
                tempUnit: String, awake: Bool?, since: Date?,
                tires: [Int]? = nil, pressureUnit: String = "", outside: Int? = nil, odometer: Int? = nil,
                addedKwh: Double? = nil, climateOn: Bool? = nil, sentryKnown: Bool = true,
                pluggedKnown: Bool = true, openKnown: Bool = true, preciseTires: [Double]? = nil,
                preciseInside: Double? = nil, preciseOutside: Double? = nil) {
        self.name = name; self.battery = battery; self.range = range; self.unit = unit
        self.chargeState = chargeState; self.plugged = plugged; self.chargerKw = chargerKw
        self.fullAt = fullAt; self.limit = limit; self.locked = locked; self.open = open
        self.tireWarning = tireWarning; self.sentry = sentry; self.place = place; self.inside = inside
        self.tempUnit = tempUnit; self.awake = awake; self.since = since; self.tires = tires
        self.pressureUnit = pressureUnit; self.outside = outside; self.odometer = odometer
        self.addedKwh = addedKwh; self.climateOn = climateOn; self.sentryKnown = sentryKnown
        self.pluggedKnown = pluggedKnown; self.openKnown = openKnown; self.preciseTires = preciseTires
        self.preciseInside = preciseInside; self.preciseOutside = preciseOutside
    }
}

/// The card's colour: all shut (green), something open (amber), a door open >= 30 min (red), not reporting (grey).
/// Shared with the Doors widget on Android (`DoorsState.kt`).
public enum DoorsTone: Sendable { case calm, warn, alert, unknown }

public enum CarFactKind: Sendable { case lock, closed, place, tires, sentry, inside }

/// One thing worth knowing about the car ("Locked", "Frunk open"); `bad` ones are drawn in amber.
public struct CarFact: Sendable, Equatable {
    public let kind: CarFactKind
    public let text: String
    public let bad: Bool
    public init(_ kind: CarFactKind, _ text: String, bad: Bool = false) { self.kind = kind; self.text = text; self.bad = bad }
}

/// Everything the car widget says — the headline, the charge line, the chips, how old the readings are.
public struct CarView: Sendable, Equatable {
    public let headline: String
    public let charge: String
    public let tone: DoorsTone
    public let facts: [CarFact]
    public let asOf: String?
    public let tires: String?
    public let subline: String
    public let charging: Bool
    public let sentry: Bool
}

public enum CarLayout: Sendable { case ring, hero, dashboard }

/// What the widget shows: the car now, or (no readings now) the last real ones, `stale`.
public struct CarShown: Sendable, Equatable {
    public let car: Car
    public let stale: Bool
    public init(car: Car, stale: Bool) { self.car = car; self.stale = stale }
}
