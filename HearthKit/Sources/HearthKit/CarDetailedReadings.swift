import Foundation

/// Availability is deliberately richer than the compact card's optional values and Booleans.
public enum CarDetailedReadingAvailability: String, Sendable, Equatable {
    case reported, unknown, unavailable, notReported, unrecognized
}

public enum CarDetailedReadingAttribution: String, Sendable, Equatable {
    case current, historical, unidentified
}

public struct CarDetailedReadingRow: Sendable, Equatable, Identifiable {
    public let id: String
    public let label: String
    public let value: String
    public let rawState: String?
    public let availability: CarDetailedReadingAvailability
    public let unit: String?
    public let unitUnavailable: Bool
    public let note: String?
    public let date: Date?
}

public struct CarDetailedReadingSection: Sendable, Equatable, Identifiable {
    public let id: String
    public let title: String
    public let rows: [CarDetailedReadingRow]
}

/// Every cohort comes from one raw reply and one independently proved observation date.
public struct CarDetailedReadingCohort: Sendable, Equatable, Identifiable {
    public let id: String
    public let title: String
    public let attribution: CarDetailedReadingAttribution
    public let name: String
    public let vehiclePrefix: String?
    public let observedAt: Date?
    public let sourceRows: [CarDetailedReadingRow]
    public let sections: [CarDetailedReadingSection]
}

public struct CarDetailedReadingAttention: Sendable, Equatable {
    public let title: String
    public let message: String?
}

/// UI-free, read-only detail rows derived from the coherent raw cache, never formatted Beacon strings.
/// This model does not authorize refreshes or commands; callers must validate the captured origin.
public struct CarDetailedReadings: Sendable, Equatable {
    public let title: String
    public let originStatus: CarOriginStatus
    public let error: String?
    public let setup: Bool
    public let sourceRows: [CarDetailedReadingRow]
    public let cohorts: [CarDetailedReadingCohort]
    public let attention: CarDetailedReadingAttention
    public let sourceNote: String

    public init(origin: CarReadingOrigin, cache: CarReadingsCache?, error: String? = nil,
                setup: Bool = false, now: Date = .now, zone: TimeZone = .current,
                locale: Locale = .current) {
        originStatus = origin.status
        self.error = error
        self.setup = setup
        sourceNote = "These are the states Home Assistant reported. A reply check time does not prove that every vehicle sensor was sampled at that time."
        let formatter = CarDetailFormatter(now: now, zone: zone, locale: locale)
        let selection = CarDetailSelection(origin: origin, cache: cache, error: error, setup: setup)
        cohorts = selection.replies.map {
            formatter.cohort($0.raw, id: $0.id, attribution: $0.attribution,
                observedAt: $0.observedAt, title: $0.title)
        }
        title = cohorts.first?.name ?? "Car readings"
        sourceRows = [
            formatter.textRow("originStatus", "Reading status", selection.statusLabel),
            formatter.textRow("vehiclePrefix", "Home Assistant vehicle prefix",
                origin.vehiclePrefix ?? "Not identified",
                note: "This is the integration's entity prefix, not a VIN."),
            formatter.dateRow("displayedObservedAt", "Displayed reading observed",
                selection.replies.first?.observedAt, missing: "Reading time unavailable"),
            formatter.dateRow("checkedAt", "Last successful reply checked", cache?.checkedAt,
                missing: "No successful reply recorded"),
            formatter.dateRow("attemptedAt", "Latest read attempt completed", origin.attemptedAt,
                missing: "Attempt time unavailable")
        ]
        attention = selection.attention
    }
}

private struct CarDetailRawReply {
    let name: String
    let prefix: String?
    let states: [String: String]
    let units: [String: String]
    let statusSince: String?

    init?(_ raw: String) {
        guard let data = raw.data(using: .utf8),
              let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let identity = carReplyIdentity(raw), identity.found,
              let states = object["s"] as? [String: String] else { return nil }
        self.states = states
        prefix = identity.vehiclePrefix
        let rawName = (object["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        name = rawName?.isEmpty == false ? rawName! : "Car"
        statusSince = object["statusSince"] as? String

        // Future coherent replies may supply per-entity units. The legacy three attributes describe
        // only their own entities; they are not evidence for another temperature, wheel or distance.
        var units = (object["units"] as? [String: String]) ?? [:]
        let legacy = [
            ("sensor.battery_range", "unit"),
            ("sensor.inside_temperature", "tempUnit"),
            ("sensor.tire_pressure_front_left", "pressureUnit")
        ]
        for (entity, attribute) in legacy where units[entity] == nil {
            units[entity] = object[attribute] as? String
        }
        self.units = units
    }

    func state(_ key: String) -> String? {
        states[key]?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    func number(_ key: String) -> Double? {
        guard let raw = states[key]?.trimmingCharacters(in: .whitespacesAndNewlines),
              let value = Double(raw), value.isFinite else { return nil }
        return value
    }

    var batteryPercentage: Double? {
        guard let value = number("sensor.battery_level"), (0...100).contains(value) else { return nil }
        return value
    }
}

private struct CarDetailSelectedReply {
    let raw: CarDetailRawReply
    let id: String
    let title: String
    let attribution: CarDetailedReadingAttribution
    let observedAt: Date?
}

private struct CarDetailSelection {
    let replies: [CarDetailSelectedReply]
    let statusLabel: String
    let attention: CarDetailedReadingAttention

    init(origin: CarReadingOrigin, cache: CarReadingsCache?, error: String?, setup: Bool) {
        let recovery: (String, String)?
        if setup || origin.status == .setup {
            recovery = ("Setup required", "Connect Home Assistant")
        } else {
            recovery = switch origin.status {
            case .noCar: ("No car found", "No car found")
            case .obsolete: ("Widget reading changed", "Widget reading changed")
            case .storageUnavailable: ("Storage unavailable", "Readings storage unavailable")
            default: nil
            }
        }
        if let recovery {
            replies = []
            statusLabel = recovery.0
            attention = CarDetailedReadingAttention(title: recovery.1, message: error)
            return
        }
        guard let cache, let current = CarDetailRawReply(cache.current) else {
            replies = []
            let headline = origin.status == .authenticationFailure ? "Sign in again"
                : origin.status == .unidentified ? "Car could not be identified"
                : error != nil ? "Read failed" : "No reading available"
            statusLabel = headline
            attention = CarDetailedReadingAttention(title: headline, message: error)
            return
        }
        let expectedPrefix = origin.vehiclePrefix?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let expectedPrefix, expectedPrefix.isEmpty == false,
           current.prefix != expectedPrefix {
            replies = []
            statusLabel = "Reading identity mismatch"
            attention = CarDetailedReadingAttention(title: statusLabel,
                message: "The stored reply does not belong to this widget reading's vehicle.")
            return
        }
        guard let expectedPrefix, expectedPrefix.isEmpty == false,
              current.prefix == expectedPrefix, origin.status != .unidentified else {
            replies = [CarDetailSelectedReply(raw: current, id: "unidentified",
                title: "Latest Home Assistant reply · Vehicle unidentified",
                attribution: .unidentified, observedAt: cache.checkedAt)]
            statusLabel = "Vehicle unidentified"
            attention = CarDetailedReadingAttention(title: "Car could not be identified", message: error)
            return
        }

        // Match the production card's whole-response fallback. No field is borrowed individually.
        // Percent validity affects detail rows/attention, never the identity of the actual displayed
        // cohort. The compact parser safely rejects unsupported numeric magnitudes before rounding.
        let displayedHistory = CarFetchResult(cache: cache, error: error).shownCar?.stale == true
            ? cache.lastGood.flatMap(CarDetailRawReply.init) : nil
        let failedAttempt = error != nil || [.failed, .authenticationFailure].contains(origin.status)
        if let displayedHistory, displayedHistory.prefix == expectedPrefix {
            replies = [
                CarDetailSelectedReply(raw: displayedHistory, id: "displayed-history",
                    title: "Displayed last-known readings", attribution: .historical,
                    observedAt: cache.historicalObservedAt),
                CarDetailSelectedReply(raw: current, id: "latest-reply",
                    title: failedAttempt ? "Latest retained Home Assistant reply" : "Latest Home Assistant reply",
                    attribution: failedAttempt ? .historical : .current,
                    observedAt: cache.checkedAt)
            ]
            statusLabel = "Last known"
            attention = CarDetailedReadingAttention(title: "Last known",
                message: error ?? "The latest reply has no battery reading. Last-known readings and the latest reply are shown separately.")
        } else {
            let historical = origin.historical || error != nil ||
                [.history, .failed, .authenticationFailure].contains(origin.status)
            replies = [CarDetailSelectedReply(raw: current, id: "displayed",
                title: historical ? "Displayed last-known readings" : "Home Assistant readings",
                attribution: historical ? .historical : .current, observedAt: cache.checkedAt)]
            statusLabel = historical ? "Last known" : origin.status == .noReading ? "No battery reading" : "Current reply"
            if historical {
                attention = CarDetailedReadingAttention(title: "Last known", message: error)
            } else {
                attention = Self.freshAttention(current)
            }
        }
    }

    private static func freshAttention(_ raw: CarDetailRawReply) -> CarDetailedReadingAttention {
        let openings: [String] = [
            ("binary_sensor.front_driver_door", "on", "Front driver door"),
            ("binary_sensor.front_passenger_door", "on", "Front passenger door"),
            ("binary_sensor.rear_driver_door", "on", "Rear driver door"),
            ("binary_sensor.rear_passenger_door", "on", "Rear passenger door"),
            ("cover.frunk", "open", "Frunk"), ("cover.trunk", "open", "Trunk"),
            ("cover.windows", "open", "Windows")
        ].compactMap { entry -> String? in
            let (key, state, label) = entry
            return raw.state(key) == state ? label : nil
        }
        let chargePort = raw.state("cover.charge_port_door") == "open" &&
            raw.state("binary_sensor.charge_cable") == "off" ? ["Charge port"] : []
        let warningOpenings = openings + chargePort
        if !warningOpenings.isEmpty {
            return CarDetailedReadingAttention(title: "Openings reported", message: warningOpenings.joined(separator: " · "))
        }
        if ["unlocked", "open"].contains(raw.state("lock.lock") ?? "") {
            return CarDetailedReadingAttention(title: "Unlocked", message: nil)
        }
        if ["front_left", "front_right", "rear_left", "rear_right"]
            .contains(where: { raw.state("binary_sensor.tire_pressure_warning_\($0)") == "on" }) {
            return CarDetailedReadingAttention(title: "Tire warning", message: "See individual wheel readings and warnings below.")
        }
        if let battery = raw.batteryPercentage, battery <= 20,
           raw.state("binary_sensor.charge_cable") == "off" {
            return CarDetailedReadingAttention(title: "Low battery", message: "\(raw.states["sensor.battery_level"]!)%")
        }
        if ["charging", "starting"].contains(raw.state("sensor.charging") ?? "") {
            return CarDetailedReadingAttention(title: raw.state("sensor.charging") == "starting" ? "Charging starting" : "Charging",
                message: raw.batteryPercentage != nil ? "\(raw.states["sensor.battery_level"]!)% battery" : "Battery reading unavailable")
        }
        if raw.batteryPercentage != nil {
            return CarDetailedReadingAttention(title: "\(raw.states["sensor.battery_level"]!)% battery", message: nil)
        }
        return CarDetailedReadingAttention(title: "No battery reading",
            message: "Other reported vehicle states remain available below.")
    }
}

private struct CarDetailField {
    enum Rendering {
        case number, percent, named([String: String]), location, estimate
    }
    let key: String
    let label: String
    let rendering: Rendering

    init(_ key: String, _ label: String, _ rendering: Rendering) {
        self.key = key; self.label = label; self.rendering = rendering
    }
}

private struct CarDetailFormatter {
    let now: Date
    let zone: TimeZone
    let locale: Locale

    private var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = zone
        formatter.dateStyle = .medium
        formatter.timeStyle = .medium
        return formatter
    }

    func textRow(_ id: String, _ label: String, _ value: String, note: String? = nil) -> CarDetailedReadingRow {
        CarDetailedReadingRow(id: id, label: label, value: value, rawState: nil,
            availability: .reported, unit: nil, unitUnavailable: false, note: note, date: nil)
    }

    func dateRow(_ id: String, _ label: String, _ date: Date?, missing: String,
                 rawState: String? = nil) -> CarDetailedReadingRow {
        CarDetailedReadingRow(id: id, label: label,
            value: date.map(dateFormatter.string) ?? missing, rawState: rawState,
            availability: date == nil ? .notReported : .reported,
            unit: nil, unitUnavailable: false, note: nil, date: date)
    }

    func cohort(_ raw: CarDetailRawReply, id: String, attribution: CarDetailedReadingAttribution,
                observedAt: Date?, title: String) -> CarDetailedReadingCohort {
        var sourceRows = [
            textRow("name", "Vehicle name", raw.name),
            textRow("prefix", "Home Assistant vehicle prefix", raw.prefix ?? "Not identified"),
            dateRow("observedAt", attribution == .historical ? "Last-known reading observed" : "Reply checked",
                observedAt, missing: "Reading time unavailable")
        ]
        if let value = raw.statusSince {
            let parsed = parseOffsetDateTime(value)
            sourceRows.append(parsed != nil
                ? dateRow("statusSince", "Awake state last changed", parsed,
                    missing: "Transition time unavailable", rawState: value)
                : CarDetailedReadingRow(id: "statusSince", label: "Awake state last changed",
                    value: value.isEmpty ? "Not reported" : "Unrecognized time: \(value)",
                    rawState: value, availability: value.isEmpty ? .notReported : .unrecognized,
                    unit: nil, unitUnavailable: false, note: nil, date: nil))
        } else {
            sourceRows.append(dateRow("statusSince", "Awake state last changed", nil,
                missing: "Transition time unavailable"))
        }
        let sections = Self.fields.map { definition in
            CarDetailedReadingSection(id: definition.id, title: definition.title,
                rows: definition.fields.map { row($0, raw: raw, attribution: attribution) })
        }
        return CarDetailedReadingCohort(id: id, title: title, attribution: attribution,
            name: raw.name, vehiclePrefix: raw.prefix, observedAt: observedAt,
            sourceRows: sourceRows, sections: sections)
    }

    private func row(_ field: CarDetailField, raw: CarDetailRawReply,
                     attribution: CarDetailedReadingAttribution) -> CarDetailedReadingRow {
        let original = raw.states[field.key]
        let trimmed = original?.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = trimmed?.lowercased()
        let availability: CarDetailedReadingAvailability
        let missing: String?
        switch normalized {
        case nil, "", "none", "null": availability = .notReported; missing = "Not reported"
        case "unknown": availability = .unknown; missing = "Unknown"
        case "unavailable": availability = .unavailable; missing = "Unavailable"
        default: availability = .reported; missing = nil
        }
        if let missing {
            return CarDetailedReadingRow(id: field.key, label: field.label, value: missing,
                rawState: original, availability: availability, unit: nil,
                unitUnavailable: false, note: nil, date: nil)
        }
        let value = trimmed!
        func unrecognized() -> CarDetailedReadingRow {
            CarDetailedReadingRow(id: field.key, label: field.label,
                value: "Unrecognized state: \(value)", rawState: original,
                availability: .unrecognized, unit: nil, unitUnavailable: false, note: nil, date: nil)
        }
        switch field.rendering {
        case .number, .percent:
            guard let number = Double(value), number.isFinite else { return unrecognized() }
            if case .percent = field.rendering {
                guard (0...100).contains(number) else { return unrecognized() }
                return CarDetailedReadingRow(id: field.key, label: field.label, value: "\(value)%",
                    rawState: original, availability: .reported, unit: "%",
                    unitUnavailable: false, note: nil, date: nil)
            }
            let candidate = raw.units[field.key]?.trimmingCharacters(in: .whitespacesAndNewlines)
            let unit = candidate.flatMap { carUnknownStates.contains($0.lowercased()) || $0.lowercased() == "null" ? nil : $0 }
            return CarDetailedReadingRow(id: field.key, label: field.label,
                value: unit.map { "\(value) \($0)" } ?? "\(value) · Unit unavailable",
                rawState: original, availability: .reported, unit: unit,
                unitUnavailable: unit == nil, note: nil, date: nil)
        case .named(let states):
            guard let name = states[normalized!] else { return unrecognized() }
            return CarDetailedReadingRow(id: field.key, label: field.label, value: name,
                rawState: original, availability: .reported, unit: nil,
                unitUnavailable: false, note: nil, date: nil)
        case .location:
            let name = normalized == "home" ? "Home" : normalized == "not_home" ? "Away" : value
            return CarDetailedReadingRow(id: field.key, label: field.label, value: name,
                rawState: original, availability: .reported, unit: nil,
                unitUnavailable: false, note: nil, date: nil)
        case .estimate:
            guard let date = parseOffsetDateTime(value) else { return unrecognized() }
            var notes = ["Recorded estimate; this does not confirm current charging."]
            if date <= now { notes.append("This estimate's time has passed.") }
            if attribution == .historical { notes.append("This estimate belongs to historical readings.") }
            return CarDetailedReadingRow(id: field.key, label: field.label,
                value: dateFormatter.string(from: date), rawState: original, availability: .reported,
                unit: nil, unitUnavailable: false, note: notes.joined(separator: " "), date: date)
        }
    }

    private struct SectionDefinition {
        let id: String
        let title: String
        let fields: [CarDetailField]
    }

    private static var fields: [SectionDefinition] {
        let door: [String: String] = ["on": "Open", "off": "Closed"]
        let cover: [String: String] = ["open": "Open", "closed": "Closed", "opening": "Opening", "closing": "Closing"]
        let warning: [String: String] = ["on": "Warning", "off": "No warning reported"]
        return [
            SectionDefinition(id: "battery", title: "Battery and charging", fields: [
                CarDetailField("sensor.battery_level", "Battery", .percent),
                CarDetailField("sensor.battery_range", "Range", .number),
                CarDetailField("number.charge_limit", "Charge limit", .percent),
                CarDetailField("sensor.charging", "Charging state", .named([
                    "charging": "Charging", "starting": "Starting", "complete": "Complete",
                    "stopped": "Stopped", "disconnected": "Disconnected", "no_power": "No power"])),
                CarDetailField("binary_sensor.charge_cable", "Charge cable", .named(["on": "Connected", "off": "Disconnected"])),
                CarDetailField("sensor.charger_power", "Charger power", .number),
                CarDetailField("sensor.time_to_full_charge", "Expected full time", .estimate),
                CarDetailField("sensor.charge_energy_added", "Energy added", .number)
            ]),
            SectionDefinition(id: "security", title: "Security and openings", fields: [
                CarDetailField("lock.lock", "Lock", .named([
                    "locked": "Locked", "unlocked": "Unlocked", "open": "Open",
                    "locking": "Locking", "unlocking": "Unlocking", "jammed": "Jammed"])),
                CarDetailField("binary_sensor.front_driver_door", "Front driver door", .named(door)),
                CarDetailField("binary_sensor.front_passenger_door", "Front passenger door", .named(door)),
                CarDetailField("binary_sensor.rear_driver_door", "Rear driver door", .named(door)),
                CarDetailField("binary_sensor.rear_passenger_door", "Rear passenger door", .named(door)),
                CarDetailField("cover.frunk", "Frunk", .named(cover)),
                CarDetailField("cover.trunk", "Trunk", .named(cover)),
                CarDetailField("cover.windows", "Windows", .named(cover)),
                CarDetailField("cover.charge_port_door", "Charge port", .named(cover)),
                CarDetailField("switch.sentry_mode", "Sentry", .named(["on": "On", "off": "Off"]))
            ]),
            SectionDefinition(id: "location", title: "Location and vehicle status", fields: [
                CarDetailField("device_tracker.location", "Location", .location),
                CarDetailField("binary_sensor.status", "Vehicle status", .named(["on": "Awake", "off": "Asleep"])),
                CarDetailField("sensor.odometer", "Odometer", .number)
            ]),
            SectionDefinition(id: "conditions", title: "Cabin and outside", fields: [
                CarDetailField("sensor.inside_temperature", "Cabin temperature", .number),
                CarDetailField("sensor.outside_temperature", "Outside temperature", .number),
                CarDetailField("climate.climate", "Climate state", .named([
                    "off": "Off", "heat": "Heat", "cool": "Cool", "heat_cool": "Heat / cool",
                    "auto": "Auto", "dry": "Dry", "fan_only": "Fan only"]))
            ]),
            SectionDefinition(id: "tires", title: "Tires", fields: [
                CarDetailField("sensor.tire_pressure_front_left", "Front left pressure", .number),
                CarDetailField("binary_sensor.tire_pressure_warning_front_left", "Front left warning", .named(warning)),
                CarDetailField("sensor.tire_pressure_front_right", "Front right pressure", .number),
                CarDetailField("binary_sensor.tire_pressure_warning_front_right", "Front right warning", .named(warning)),
                CarDetailField("sensor.tire_pressure_rear_left", "Rear left pressure", .number),
                CarDetailField("binary_sensor.tire_pressure_warning_rear_left", "Rear left warning", .named(warning)),
                CarDetailField("sensor.tire_pressure_rear_right", "Rear right pressure", .number),
                CarDetailField("binary_sensor.tire_pressure_warning_rear_right", "Rear right warning", .named(warning))
            ])
        ]
    }
}
