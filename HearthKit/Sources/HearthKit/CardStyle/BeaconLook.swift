import Foundation

/// Everything a Beacon card (Alarm, Thermostat, Car, ChargePoint) needs to draw its BODY in a style.
/// Ported from Android's `beaconLook` in `BeaconChrome.kt`.
///
/// The rail is not here on purpose: it always keeps the widget's own state colour and ink
/// (`BeaconTone`; ChargePoint's orange), so no style can reach it.
public struct BeaconLook: Sendable, Equatable {
    public let body: CardSurface
    public let ink: UInt32
    public let soft: UInt32
    public let faint: UInt32
    /// Flat chip (Mode / Fan / Resume, Arm home / away).
    public let chip: UInt32
    /// Faint chip (the door well, a disabled chip).
    public let chipFaint: UInt32
    /// The bright primary pill (Disarm).
    public let chipPrimary: UInt32
    public let chipPrimaryInk: UInt32
    /// Heat setpoint.
    public let heat: UInt32
    /// Cool setpoint.
    public let cool: UInt32
    /// A locked door.
    public let secure: UInt32
    /// An unlocked door, Sentry on.
    public let alert: UInt32
    public let light: Bool
    public let textScale: CGFloat
    public let smallPrint: Bool
}

private enum BeaconBody {
    /// `beacon_raised_body.xml`.
    static let status = CardSurface(fill: .solid(BeaconSurfaceColors.graphiteARGB))
    /// `beacon_raised_body_light.xml`.
    static let light = CardSurface(fill: .diagonal(start: 0xFFFEFCF4, centre: 0xFFF2F1E6, end: 0xFFDFE5D9))
    /// A solid fill under `beacon_raised_body_glaze.xml`.
    static let black = CardSurface(fill: .solid(CardSurface.blackARGB),
                                   glaze: .diagonal(start: 0x14FFFFFF, centre: 0x00000000, end: 0x18000000))
}

/// The look of a Beacon card's body for `style`.
public func beaconLook(_ style: CardStyle) -> BeaconLook {
    let light = if case .colour(let colour) = style.background { colour.isLight } else { false }
    let body: CardSurface = switch style.background {
    case .status: BeaconBody.status
    case .colour(let colour): colour.isLight ? BeaconBody.light : .colour(colour)
    case .black: BeaconBody.black
    }
    return BeaconLook(
        body: body,
        ink: light ? 0xFF26342C : 0xFFF2F5ED,
        soft: light ? 0xFF56665B : 0xFFB9C8BC,
        faint: light ? 0xFF79847A : 0xFF829587,
        chip: light ? 0x14000000 : 0x1AFFFFFF,
        chipFaint: light ? 0x0D000000 : 0x12FFFFFF,
        chipPrimary: light ? 0xFF2A2A2A : 0xFFF0F0F0,
        chipPrimaryInk: light ? 0xFFF0F0F0 : 0xFF1C1C1A,
        heat: light ? 0xFF855016 : 0xFFF6D58A,
        cool: light ? 0xFF316D85 : 0xFFA6D5FF,
        secure: light ? 0xFF2D633F : 0xFF8FD6A8,
        alert: light ? 0xFFB3261E : BeaconSurfaceColors.sentryOnARGB,
        light: light,
        textScale: style.textSize.scale,
        smallPrint: style.smallPrint)
}
