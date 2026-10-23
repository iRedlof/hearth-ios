import Foundation

public enum SentryState: String, Sendable { case on, off, unknown }

/// Everything the Car Beacon view renders, already formatted. The view-model (`carView`) maps the
/// raw `Car` + Home Assistant readings onto this; the SwiftUI view stays dumb. Mirrors the Android
/// car widget's displayed fields (v1.4.28).
public struct CarSnapshot: Sendable, Equatable {
    public var name: String          // header, e.g. "Stargate"
    public var checkedAt: String     // "3:47 PM"
    public var battery: Int?         // 72  (nil → "—")
    public var range: String         // "219 mi range"
    public var lock: String          // "Locked" / "Unlocked" / "—"
    public var lockWarn: Bool        // unlocked
    public var doors: String         // "All shut" / "2 open" / "—"
    public var doorsWarn: Bool       // something open
    public var cabin: String         // "68°F"
    public var outside: String       // "52.7°F"
    public var tires: String         // "38–39 psi"
    public var tiresWarn: Bool
    public var place: String         // "Home · Awake" / "Home · asleep since 10:59 PM"
    public var sentry: SentryState   // on → red icon+word, off/unknown → neutral
    public var chargeLine: String    // "Unplugged" / "Charging · 7 kW" / "Low battery"
    public var tone: BeaconTone      // left-panel fill/ink + the charge-bar fill

    public init(name: String, checkedAt: String, battery: Int?, range: String,
                lock: String, lockWarn: Bool, doors: String, doorsWarn: Bool,
                cabin: String, outside: String, tires: String, tiresWarn: Bool,
                place: String, sentry: SentryState, chargeLine: String, tone: BeaconTone) {
        self.name = name; self.checkedAt = checkedAt; self.battery = battery; self.range = range
        self.lock = lock; self.lockWarn = lockWarn; self.doors = doors; self.doorsWarn = doorsWarn
        self.cabin = cabin; self.outside = outside; self.tires = tires; self.tiresWarn = tiresWarn
        self.place = place; self.sentry = sentry; self.chargeLine = chargeLine; self.tone = tone
    }

    /// Realistic sample for previews / the gallery — matches the on-device v1.4.28 screenshot.
    public static let sample = CarSnapshot(
        name: "Stargate", checkedAt: "3:47 PM", battery: 72, range: "219 mi range",
        lock: "Locked", lockWarn: false, doors: "All shut", doorsWarn: false,
        cabin: "68°F", outside: "52.7°F", tires: "38–39 psi", tiresWarn: false,
        place: "Home · asleep since 10:59 PM", sentry: .on, chargeLine: "Unplugged", tone: .mint)
}
