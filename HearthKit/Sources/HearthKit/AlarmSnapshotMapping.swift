import Foundation

/// Maps the raw alarm + front-door states onto the display `AlarmSnapshot`, using the ported view-model.
public func alarmSnapshot(alarm: AlarmState?, lockState: String?, lockChanged: Date?, name: String,
                          error: String?, checkedAt: Date?, now: Date,
                          zone: TimeZone = .current, locale: Locale = .current,
                          doorName: String = "Door", doorSelected: Bool? = nil,
                          doorError: String? = nil, doorCheckedAt: Date? = nil) -> AlarmSnapshot {
    let stale = alarmStale(alarm?.state, error)
    let card = cardFor(alarm?.state, error: error, changedAt: alarm?.lastChanged,
                       checkedAt: checkedAt, now: now, zone: zone, locale: locale)
    let tone = beaconAlarmPair(alarm?.state, stale: stale)
    let glyph = beaconAlarmGlyph(statusFor(alarm?.state).tone)
    let lock = lockStatusFor(lockState)

    let timeFmt = DateFormatter(); timeFmt.locale = locale; timeFmt.timeZone = zone; timeFmt.dateFormat = "h:mm a"
    let checkedStr = checkedAt.map { timeFmt.string(from: $0) } ?? "—"

    let selected = doorSelected ?? (lockState != nil)
    let historicalDoor = doorError != nil && lockState != nil
    var snapshot = AlarmSnapshot(
        name: name,
        checkedAt: checkedStr,
        stateWord: card.title,
        detail: card.detail ?? "",
        tone: tone,
        glyph: glyph,
        doorName: selected ? doorName : "No door selected",
        doorState: selected ? lock.title : "Choose in Settings",
        doorSince: historicalDoor
            ? sinceLabel(doorCheckedAt, now: now, zone: zone, locale: locale)?
                .replacingOccurrences(of: "since ", with: "Last checked ")
            : sinceLabel(lockChanged, now: now, zone: zone, locale: locale),
        doorLocked: selected ? lock.secure : nil,
        actions: error == nil ? alarmAvailableActions(alarm) : [])
    snapshot.setup = error?.hasPrefix("Set up") == true
    snapshot.stale = stale
    snapshot.error = error
    snapshot.doorSelected = selected
    snapshot.doorStale = historicalDoor
    snapshot.doorError = doorError
    snapshot.doorAction = selected && doorError == nil ? lockActionFor(lockState) : nil
    snapshot.needsSettings = snapshot.setup || error.map(beaconNeedsSettings) == true
        || doorError.map(beaconNeedsSettings) == true
    snapshot.needsSignIn = error.map(beaconNeedsSignIn) == true
        || doorError.map(beaconNeedsSignIn) == true
    return snapshot
}
