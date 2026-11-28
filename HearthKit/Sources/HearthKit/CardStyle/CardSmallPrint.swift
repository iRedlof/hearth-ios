import Foundation

/// What "Small print" hides, decided once here so every view agrees with Android.

/// The "Checked 9:41 AM" stamp is small print; "Checking…" always shows (`BeaconChrome.kt:248`).
public func cardShowsCheckedStamp(smallPrint: Bool, checking: Bool = false) -> Bool {
    smallPrint || checking
}

/// ChargePoint's context lines under the rail's answer (`ChargePointWidget.kt:55`).
public func cpContextLines(_ lines: [String], smallPrint: Bool) -> [String] {
    smallPrint ? lines : []
}

/// Activity drops who did it, "by …" (`ActivityWidget.kt:77`).
public func activityItems(_ items: [ActivityItem], smallPrint: Bool) -> [ActivityItem] {
    guard !smallPrint else { return items }
    return items.map {
        ActivityItem(at: $0.at, kind: $0.kind, text: $0.text, by: nil, entityId: $0.entityId,
                     name: $0.name, action: $0.action, eventKey: $0.eventKey)
    }
}
