import Foundation

/// The point size iOS gives a Home Screen widget on an iPhone of a given screen width (Apple's
/// published widget sizes). In-app previews draw at this size, so a preview is the same box the
/// real widget has to fit — a smaller box made content overflow and look broken.
public struct HomeScreenWidgetSize: Equatable, Sendable {
    public let medium: (width: Double, height: Double)
    public let large: (width: Double, height: Double)

    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.medium == rhs.medium && lhs.large == rhs.large
    }
}

public func homeScreenWidgetSize(screenWidth: Double) -> HomeScreenWidgetSize {
    switch screenWidth {
    case 428...: HomeScreenWidgetSize(medium: (364, 170), large: (364, 382))
    case 414..<428: HomeScreenWidgetSize(medium: (360, 169), large: (360, 379))
    case 390..<414: HomeScreenWidgetSize(medium: (338, 158), large: (338, 354))
    case 360..<390: HomeScreenWidgetSize(medium: (329, 155), large: (329, 345))
    default: HomeScreenWidgetSize(medium: (292, 141), large: (292, 311))
    }
}
