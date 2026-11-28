import SwiftUI

/// The corner the app draws a widget with where WidgetKit is not there to give it one.
enum WidgetContainer {
    static let cornerRadius: CGFloat = 22
}

extension View {
    /// Hosts a widget view in the app the way WidgetKit hosts it on the Home Screen: at the widget's
    /// size, inside a rounded container, clipped to it.
    ///
    /// The widget views draw their card and its strokes with `ContainerRelativeShape`. WidgetKit
    /// supplies that container on the Home Screen. In the app nothing did, so the shape resolved
    /// against whatever was around the view (a sheet, a scroll view) and came out inset or with odd
    /// corners. Every in-app host of a widget view goes through here.
    func widgetContainer(size: CGSize, cornerRadius: CGFloat = WidgetContainer.cornerRadius) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        return frame(width: size.width, height: size.height)
            .containerShape(shape)
            .clipShape(shape)
    }
}
