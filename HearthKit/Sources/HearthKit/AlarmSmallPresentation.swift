import Foundation

public struct AlarmSmallContent: Sendable, Equatable {
    public let snapshot: AlarmSnapshot
    public let criticalTexts: [String]
    public let optionalContext: String?
    public let tone: BeaconTone
    public let statusSymbol: String
    public let historical: Bool
    public let navigationURL: URL?
}

/// Panel and door priority is based on original raw states, not colors, action slots or formatted copy.
public func alarmSmallContent(_ snapshot: AlarmSnapshot,
                              destination: AlarmReadingsDestination = .inert) -> AlarmSmallContent {
    let panelFresh = snapshot.panelRawState != nil && snapshot.error == nil && !snapshot.stale && !snapshot.storageUnavailable
    let doorFresh = snapshot.doorSelected && snapshot.doorRawState != nil && snapshot.doorError == nil && !snapshot.doorStale
    let panelSignIn = snapshot.error.map(beaconNeedsSignIn) == true
    let historical = !panelFresh && snapshot.panelRawState != nil && !snapshot.storageUnavailable && !snapshot.setup
    let stateLabels: [String: String] = ["disarmed": "Disarmed", "armed_home": "Armed home",
        "armed_away": "Armed away", "armed_night": "Armed night", "armed_vacation": "Armed vacation",
        "armed_custom_bypass": "Armed (bypass)", "triggered": "Alarm triggered", "pending": "Entry delay",
        "arming": "Arming", "disarming": "Disarming"]
    var panelLabels: [String]
    if snapshot.storageUnavailable { panelLabels = ["Unavailable"] }
    else if snapshot.setup { panelLabels = ["Set up"] }
    else if historical { panelLabels = panelSignIn ? ["Last known", "Sign in"] : ["Last known"] }
    else if panelSignIn { panelLabels = ["Sign in"] }
    else if !panelFresh { panelLabels = ["No reading"] }
    else { panelLabels = [stateLabels[snapshot.panelRawState ?? ""] ?? "Unavailable"] }

    var labels = panelLabels
    var tone = panelFresh && stateLabels[snapshot.panelRawState ?? ""] != nil ? snapshot.tone : .offline
    var symbol = historical && !panelSignIn ? "clock" : "exclamationmark.shield"
    var context: String?
    if panelFresh && snapshot.panelRawState == "triggered" {
        symbol = "exclamationmark.shield"
    } else if doorFresh, let door = snapshot.doorRawState,
              ["unlocked", "open", "jammed"].contains(door) {
        labels = ["Door " + door]
        tone = .yellow; symbol = "exclamationmark.shield"
        if panelLabels != [stateLabels[snapshot.panelRawState ?? ""] ?? ""] || !panelFresh {
            labels += panelLabels
        } else { context = panelLabels.first }
    } else if panelFresh, let raw = snapshot.panelRawState, stateLabels[raw] != nil {
        symbol = ["pending", "arming", "disarming"].contains(raw) ? "hourglass" : raw == "armed_away" ? "car" : "shield"
    }
    if snapshot.commandPending {
        labels.append("Updating")
        if panelFresh && ["shield", "car"].contains(symbol) { symbol = "hourglass" }
    }
    else if snapshot.commandError != nil { labels.append("Not confirmed"); symbol = "exclamationmark.shield" }
    if case .unavailable = destination { labels.append("Not saved"); symbol = "exclamationmark.shield" }

    if context == nil {
        if historical { context = stateLabels[snapshot.panelRawState ?? ""] }
        else if snapshot.doorSelected {
            if snapshot.doorError != nil || snapshot.doorStale {
                context = snapshot.doorRawState == nil ? "Door unavailable" : "Door last known"
            } else if let raw = snapshot.doorRawState {
                let supported = ["locked", "unlocked", "open", "jammed", "locking", "unlocking", "opening"]
                context = supported.contains(raw) ? snapshot.doorName + " " + raw : "Door unavailable"
            } else { context = "Door unavailable" }
        } else { context = "No door selected" }
    }
    return AlarmSmallContent(snapshot: snapshot, criticalTexts: labels, optionalContext: context,
        tone: tone, statusSymbol: symbol, historical: historical,
        navigationURL: alarmReadingsURL(for: destination))
}

public func alarmSmallAccessibility(_ content: AlarmSmallContent) -> String {
    let snapshot = content.snapshot
    var parts = ["Home Alarm", snapshot.name] + content.criticalTexts
    parts.append("Panel: " + (snapshot.panelRawState ?? "No reading"))
    if let error = snapshot.error { parts.append("Panel: " + error) }
    if let date = snapshot.panelObservedAt {
        parts.append("Panel observed: " + date.formatted(date: .abbreviated, time: .standard))
    }
    if snapshot.doorSelected {
        parts.append(snapshot.doorName + ": " + (snapshot.doorRawState ?? "No reading"))
        if snapshot.doorStale { parts.append("Door last known") }
        if let error = snapshot.doorError { parts.append("Door: " + error) }
        if let date = snapshot.doorObservedAt {
            parts.append("Door observed: " + date.formatted(date: .abbreviated, time: .standard))
        }
    } else { parts.append("No door selected") }
    if let operation = snapshot.operation {
        parts.append("Operation \(operation.action) for \(operation.entityID)")
    }
    if let feedback = snapshot.commandFeedback { parts.append(feedback) }
    if let error = snapshot.commandError { parts.append(error) }
    parts.append(content.navigationURL == nil ? "Example, inactive" : "Open alarm readings")
    return parts.joined(separator: ". ")
}
