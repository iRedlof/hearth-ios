import Foundation
import HearthKit

/// Converts widget snapshots to GlanceFeed entries for the Glance widget.
/// Each widget provider calls the appropriate mapper when it refreshes.

// MARK: - Car

func glanceFeed(from car: CarSnapshot, checkedAt: Date) -> GlanceFeed {
    // Error state
    if car.error != nil {
        return GlanceFeed(
            kind: .car,
            checkedAt: checkedAt,
            error: true,
            items: [],
            calm: false
        )
    }

    var items: [GlanceItem] = []
    var calm = true

    // Check for unlocked/open
    if car.lockWarn {
        items.append(GlanceItem(text: "Car \(car.lock.lowercased())", severity: .warn))
        calm = false
    }

    if car.doorsWarn {
        items.append(GlanceItem(text: "Car \(car.doors.lowercased())", severity: .warn))
        calm = false
    }

    // Check for low battery
    if let battery = car.battery, battery < 20 {
        items.append(GlanceItem(text: "Car battery \(battery)%", severity: .warn))
        calm = false
    }

    return GlanceFeed(
        kind: .car,
        checkedAt: checkedAt,
        error: false,
        items: items,
        calm: calm
    )
}

// MARK: - Alarm

func glanceFeed(from alarm: AlarmSnapshot, checkedAt: Date) -> GlanceFeed {
    // Error state
    if alarm.error != nil {
        return GlanceFeed(
            kind: .alarm,
            checkedAt: checkedAt,
            error: true,
            items: [],
            calm: false
        )
    }

    var items: [GlanceItem] = []
    var calm = true

    // Alarm triggered is ALARM severity
    if alarm.stateWord.contains("triggered") || alarm.stateWord.contains("Alarm") {
        items.append(GlanceItem(text: "Alarm triggered!", severity: .alarm))
        calm = false
    }
    // Disarmed might be a warning depending on context (not implemented yet - assume calm when disarmed)
    // Armed states are calm

    // Check front door
    if let locked = alarm.doorLocked, !locked {
        items.append(GlanceItem(text: "\(alarm.doorName) unlocked", severity: .warn))
        calm = false
    }

    return GlanceFeed(
        kind: .alarm,
        checkedAt: checkedAt,
        error: false,
        items: items,
        calm: calm
    )
}

// MARK: - Doors

func glanceFeed(from doors: DoorsSnapshot, checkedAt: Date) -> GlanceFeed {
    // Error state
    if doors.error != nil {
        return GlanceFeed(
            kind: .doors,
            checkedAt: checkedAt,
            error: true,
            items: [],
            calm: false
        )
    }

    var items: [GlanceItem] = []
    var calm = true

    // Check each door item from the summary rows
    for row in doors.summary.rows {
        // Open/unlocked doors are warnings (check status or open flag)
        let isWarning = row.status.lowercased().contains("open") ||
                       row.status.lowercased().contains("unlocked") ||
                       row.open == true
        if isWarning {
            items.append(GlanceItem(text: "\(row.name) \(row.status.lowercased())", severity: .warn))
            calm = false
        }
    }

    return GlanceFeed(
        kind: .doors,
        checkedAt: checkedAt,
        error: false,
        items: items,
        calm: calm
    )
}

// MARK: - ChargePoint

func glanceFeed(from cp: CpSnapshot, checkedAt: Date) -> GlanceFeed {
    var items: [GlanceItem] = []
    var calm = true

    // Check for significant states that need attention
    // "Your turn" means you need to respond
    if cp.bigAnswer.contains("Your turn") || cp.sub.contains("Respond now") {
        items.append(GlanceItem(text: "ChargePoint: \(cp.bigAnswer)", severity: .act))
        calm = false
    }

    // If there are rail notes (like "Move by X"), that's actionable
    if !cp.railNotes.isEmpty {
        for note in cp.railNotes {
            items.append(GlanceItem(text: note, severity: .warn))
            calm = false
        }
    }

    return GlanceFeed(
        kind: .chargePoint,
        checkedAt: checkedAt,
        error: false,
        items: items,
        calm: calm
    )
}
