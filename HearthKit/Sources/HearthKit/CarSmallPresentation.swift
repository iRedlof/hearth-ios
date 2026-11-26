import Foundation

/// Compact facts from the same whole reply that supplies the displayed car. Range is deliberately
/// absent: the compact adapter's default unit does not establish reported-unit provenance.
public struct CarSmallReading: Sendable, Equatable {
    public let name: String
    public let battery: Int?
    public let openings: [String]
    public let openingsKnown: Bool
    public let observedAt: Date?

    public init(name: String, battery: Int?, openings: [String], openingsKnown: Bool, observedAt: Date?) {
        self.name = name
        self.battery = battery.flatMap { (0...100).contains($0) ? $0 : nil }
        self.openings = openings
        self.openingsKnown = openingsKnown
        self.observedAt = observedAt
    }
}

/// Recovery and identity failures cannot acquire telemetry merely because a cache still exists.
public func carSmallReading(result: CarFetchResult, primary: CarReadingsPrimary) -> CarSmallReading? {
    switch primary {
    case .battery, .openings, .unlocked, .tireWarning, .lowBattery, .charging, .lastKnown:
        guard let shown = result.shownCar else { return nil }
        let raw = shown.stale ? result.cache?.lastGood : result.cache?.current
        return CarSmallReading(name: shown.car.name, battery: carSmallBattery(raw),
            openings: shown.car.open, openingsKnown: shown.car.openKnown,
            observedAt: result.displayedObservedAt)
    default: return nil
    }
}

/// Validate before compact rounding: 100.4 and -0.4 must not become valid 100% and 0%.
/// The caller selects the same whole reply as CarShown, rather than borrowing an individual field.
private func carSmallBattery(_ raw: String?) -> Int? {
    guard let raw, let data = raw.data(using: .utf8),
          let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
          let states = object["s"] as? [String: String],
          let text = states["sensor.battery_level"],
          let value = Double(text.trimmingCharacters(in: .whitespacesAndNewlines)),
          value.isFinite, (0...100).contains(value) else { return nil }
    return Int(value.rounded())
}

public struct CarSmallContent: Sendable, Equatable {
    public let name: String
    public let criticalTexts: [String]
    public let battery: String?
    public let batteryIsPrimary: Bool
    public let openingDetail: String?
    public let openingsKnown: Bool
    public let openingsUnknown: Bool
    public let historical: Bool
    public let observedAt: Date?
    public let tone: BeaconTone
    public let statusSymbol: String
    public let navigationURL: URL?
    public let reportedOpenings: [String]
}

/// Selects content without consulting another cache or deriving raw facts from display strings.
public func carSmallContent(_ payload: CarReadingsEntryPayload) -> CarSmallContent {
    let reading = payload.smallReading
    var labels: [String]
    var tone: BeaconTone = .offline
    var symbol = "exclamationmark.circle"
    var battery: String?
    var batteryIsPrimary = false
    var acceptsReading = false
    var historical = false
    let known = reading?.openingsKnown == true
    switch payload.primary {
    case .setup: labels = ["Set up"]
    case .signIn: labels = ["Sign in"]
    case .noCar: labels = ["No car"]
    case .changed: labels = ["Changed"]
    case .unidentified, .identityMismatch: labels = ["Check car"]
    case .storageUnavailable: labels = ["Unavailable"]
    case .readFailed, .noReading: labels = ["No reading"]
    case .lastKnown(let authenticationRequired):
        labels = authenticationRequired ? ["Last known", "Sign in"] : ["Last known"]
        historical = true
        acceptsReading = true
        symbol = authenticationRequired ? "exclamationmark.circle" : "clock"
    case .openings:
        labels = ["Openings"]; tone = .yellow; acceptsReading = true
    case .unlocked:
        labels = ["Unlocked"]; tone = .yellow; acceptsReading = true
    case .tireWarning:
        labels = ["Check tires"]; tone = .yellow; acceptsReading = true
    case .lowBattery:
        labels = ["Low battery"]; tone = .red; acceptsReading = true
    case .charging(let starting):
        labels = [starting ? "Starting" : "Charging"]
        tone = known ? .blue : .slate; symbol = "bolt"; acceptsReading = true
    case .battery(let value):
        if value.isFinite, (0...100).contains(value) {
            labels = []
            battery = "\(Int(value.rounded()))%"
            batteryIsPrimary = true
            tone = known ? .mint : .slate
            symbol = "car"
            acceptsReading = true
        } else { labels = ["No reading"] }
    }
    if acceptsReading, battery == nil, let value = reading?.battery {
        battery = "\(value)%"
    }
    if payload.readingsUnavailable {
        labels.append("Not saved")
        symbol = "exclamationmark.circle"
    }
    return CarSmallContent(name: acceptsReading ? reading?.name ?? payload.snapshot.name : payload.snapshot.name,
        criticalTexts: labels, battery: battery, batteryIsPrimary: batteryIsPrimary,
        openingDetail: payload.primary == .openings && reading?.openings.isEmpty == false
            ? reading?.openings.joined(separator: " · ") : nil,
        openingsKnown: acceptsReading && known,
        openingsUnknown: acceptsReading && !known, historical: historical,
        observedAt: acceptsReading ? reading?.observedAt : nil, tone: tone,
        statusSymbol: symbol, navigationURL: carReadingsURL(for: payload.destination),
        reportedOpenings: acceptsReading ? reading?.openings ?? [] : [])
}

public func carSmallAccessibility(_ content: CarSmallContent) -> String {
    var parts = ["Car", content.name] + content.criticalTexts
    if let battery = content.battery { parts.append("Battery \(battery)") }
    if !content.reportedOpenings.isEmpty {
        parts.append((content.historical ? "Last reported openings: " : "Reported openings: ")
            + content.reportedOpenings.joined(separator: ", "))
    } else if content.openingsKnown {
        parts.append(content.historical ? "Last known opening readings reported" : "Opening readings reported")
    }
    if content.openingsUnknown { parts.append("Openings unknown") }
    if let date = content.observedAt {
        parts.append((content.historical ? "Last known reading: " : "Reading: ")
            + date.formatted(date: .abbreviated, time: .shortened))
    }
    parts.append(content.navigationURL == nil ? "Example, inactive" : "Open readings")
    return parts.joined(separator: ". ")
}
