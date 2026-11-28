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
