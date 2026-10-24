import CoreGraphics

/// The horizontal split of a Beacon card, ported 1:1 from Android `beaconMetrics` (BeaconMetrics.kt).
/// The colored hero ("rail") is a FIXED-width band — ~130/352 ≈ 36.9% of the card width at the 352-dp
/// reference, NOT half. It scales down below 352 (`sx`) and grows slightly up to 403 (`t`). All four
/// beacon widgets (Car / Alarm / Thermostat / ChargePoint) share this identical split.
public struct BeaconSplit: Sendable, Equatable {
    public let rail: CGFloat     // left colored hero band width
    public let inset: CGFloat    // gutter after the rail, and the right margin
    public let panel: CGFloat    // right detail panel width = width − rail − 2·inset
    public let leftPad: CGFloat  // hero content inset inside the rail
}

/// Android: `railDp = (130 + 16·t)·sx`, `leftPad = (14 + 2·t)·sx`, `rightInset = (12 + 2·t)·sx`,
/// where `sx = min(1, W/352)` and `t = clamp((W − 352)/51, 0, 1)`.
public func beaconSplit(width: CGFloat) -> BeaconSplit {
    guard width > 0 else { return BeaconSplit(rail: 0, inset: 0, panel: 0, leftPad: 0) }
    let sx = min(1, width / 352)
    let t = max(0, min(1, (width - 352) / 51))
    let rail = (130 + 16 * t) * sx
    let leftPad = (14 + 2 * t) * sx
    let inset = (12 + 2 * t) * sx
    let panel = width - rail - 2 * inset
    return BeaconSplit(rail: rail, inset: inset, panel: max(0, panel), leftPad: leftPad)
}
