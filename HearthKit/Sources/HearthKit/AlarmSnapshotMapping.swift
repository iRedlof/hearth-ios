import Foundation

/// Maps the raw alarm + front-door states onto the display `AlarmSnapshot`, using the ported view-model.
public func alarmSnapshot(alarm: AlarmState?, lockState: String?, lockChanged: Date?, name: String,
                          error: String?, checkedAt: Date?, now: Date,
                          zone: TimeZone = .current, locale: Locale = .current) -> AlarmSnapshot {
    let stale = alarmStale(alarm?.state, error)
    let card = cardFor(alarm?.state, error: error, changedAt: alarm?.lastChanged,
                       checkedAt: checkedAt, now: now, zone: zone, locale: locale)
    let tone = beaconAlarmPair(alarm?.state, stale: stale)
    let glyph = beaconAlarmGlyph(statusFor(alarm?.state).tone)
    let lock = lockStatusFor(lockState)

    let timeFmt = DateFormatter(); timeFmt.locale = locale; timeFmt.timeZone = zone; timeFmt.dateFormat = "h:mm a"
    let checkedStr = checkedAt.map { timeFmt.string(from: $0) } ?? "—"

    return AlarmSnapshot(
        name: name,
        checkedAt: checkedStr,
        stateWord: card.title,
        detail: card.detail ?? "",
        tone: tone,
        glyph: glyph,
        doorName: "Front Door",
        doorState: lock.title,
        doorSince: sinceLabel(lockChanged, now: now, zone: zone, locale: locale),
        doorLocked: lock.secure,
        actions: actionsFor(alarm?.state))
}
