import SwiftUI
import WidgetKit
import HearthKit

/// Draws a widget in its Card style: the kind's own, else All cards'. Every widget kind goes
/// through here, so none can forget the style.
///
/// Every widget is a Beacon card: it paints its own body in the style and its rail in the state
/// colour, over a graphite container.
///
/// The style is resolved in `init`, not in `body`: a store lookup inside a WidgetKit configuration
/// body pushes it past the Swift type-checker's limit.
struct CardStyledContent<Content: View>: View {
    private let style: CardStyle
    private let content: Content

    init(beacon kind: HomeWidgetKind, @ViewBuilder content: () -> Content) {
        self.style = CardStyleStore.effectiveStyle(for: kind)
        self.content = content()
    }

    var body: some View {
        content
            .cardStyle(style)
            .containerBackground(for: .widget) { Color(argb: BeaconSurfaceColors.graphiteARGB) }
    }
}
