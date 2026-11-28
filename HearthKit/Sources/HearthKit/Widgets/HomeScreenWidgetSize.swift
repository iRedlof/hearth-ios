import Foundation

/// The point size iOS gives a medium Home Screen widget on an iPhone of a given screen width
/// (Apple's published widget sizes). Every Hearth widget is medium. In-app previews draw at this
/// size, so a preview is the same box the real widget has to fit — a smaller box made content
/// overflow and look broken.
public struct HomeScreenWidgetSize: Equatable, Sendable {
    public let width: Double
    public let height: Double

    public init(width: Double, height: Double) {
        self.width = width; self.height = height
    }
}

public func homeScreenWidgetSize(screenWidth: Double) -> HomeScreenWidgetSize {
    switch screenWidth {
    case 428...: HomeScreenWidgetSize(width: 364, height: 170)
    case 414..<428: HomeScreenWidgetSize(width: 360, height: 169)
    case 390..<414: HomeScreenWidgetSize(width: 338, height: 158)
    case 360..<390: HomeScreenWidgetSize(width: 329, height: 155)
    default: HomeScreenWidgetSize(width: 292, height: 141)
    }
}
