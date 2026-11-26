import Foundation

/// A bounding box around a point (± half a span), for the map `stations` query. Android's AREA_SPAN
/// is ≈ 0.022°.
public func cpBounds(lat: Double, lon: Double, span: Double = 0.022) -> CpBounds {
    CpBounds(swLat: lat - span / 2, swLon: lon - span / 2, neLat: lat + span / 2, neLon: lon + span / 2)
}

/// The `waitlist/join` body for a chosen location — joins every charger there, as the CP app does.
/// Ported from Android `cpJoinBody`.
public func cpJoinBody(_ loc: CpLocation, screenWidth: Int = 1080, screenHeight: Int = 2048) -> [String: Any] {
    ["neLat": loc.bounds.neLat, "neLon": loc.bounds.neLon, "swLat": loc.bounds.swLat, "swLon": loc.bounds.swLon,
     "screenWidth": screenWidth, "screenHeight": screenHeight,
     "deviceLocationLat": NSNull(), "deviceLocationLon": NSNull(),
     "deviceIds": loc.deviceIds, "deviceData": [:], "mobileFilter": [:]]
}
