import SwiftUI
import WidgetKit
import HearthKit

/// Draws a widget in its Card style: the kind's own, else All cards'. Every widget kind and size
/// goes through here, so none can forget the style.
///
/// The style is resolved in `init`, not in `body`: a store lookup inside a WidgetKit configuration
/// body pushes it past the Swift type-checker's limit.
struct CardStyledContent<Content: View>: View {
    private let style: CardStyle
    private let containerARGB: UInt32
    private let content: Content

    /// A non-Beacon card: the container follows the chosen background, else the card's own
    /// `statusARGB`.
    init(kind: HomeWidgetKind, statusARGB: UInt32, @ViewBuilder content: () -> Content) {
        let style = CardStyleStore.effectiveStyle(for: kind)
        self.style = style
        self.containerARGB = cardContainerARGB(style, statusARGB: statusARGB)
        self.content = content()
    }

    /// A Beacon card (Alarm, Thermostat, Car, ChargePoint): the card paints its own body in the
    /// style and its rail in the state colour, over a graphite container.
    init(beacon kind: HomeWidgetKind, @ViewBuilder content: () -> Content) {
        self.style = CardStyleStore.effectiveStyle(for: kind)
        self.containerARGB = BeaconSurfaceColors.graphiteARGB
        self.content = content()
    }

    var body: some View {
        content
            .cardStyle(style)
            .containerBackground(for: .widget) { Color(argb: containerARGB) }
    }
}
