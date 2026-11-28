import SwiftUI
import HearthKit

/// One fill from a card look.
struct CardFillView: View {
    let fill: CardFill

    var body: some View {
        switch fill {
        case .solid(let argb):
            Color(argb: argb)
        case .vertical(let top, let bottom):
            LinearGradient(colors: [Color(argb: top), Color(argb: bottom)], startPoint: .top, endPoint: .bottom)
        case .diagonal(let start, let centre, let end):
            LinearGradient(colors: [Color(argb: start), Color(argb: centre), Color(argb: end)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }
}

/// A styled background: the fill, its lighting, then its edge, clipped to `shape`.
/// The numbers all come from HearthKit (`CardSurface`); this only draws them.
struct CardSurfaceView<Outline: InsettableShape>: View {
    let surface: CardSurface
    let shape: Outline

    var body: some View {
        CardFillView(fill: surface.fill)
            .overlay { glaze }
            .overlay(alignment: .top) { sheen }
            .overlay { stroke }
            .clipShape(shape)
    }

    @ViewBuilder private var glaze: some View {
        if let glaze = surface.glaze { CardFillView(fill: glaze) }
    }

    @ViewBuilder private var sheen: some View {
        if let sheen = surface.sheen {
            LinearGradient(colors: [Color(argb: sheen.topARGB), Color(argb: sheen.centreARGB),
                                    Color(argb: sheen.bottomARGB)], startPoint: .top, endPoint: .bottom)
                .frame(height: sheen.height)
        }
    }

    @ViewBuilder private var stroke: some View {
        if let argb = surface.strokeARGB {
            shape.strokeBorder(Color(argb: argb), lineWidth: CardSurface.strokeWidth)
        }
    }
}

extension CardSurfaceView where Outline == ContainerRelativeShape {
    /// The whole card: follows the widget's own corners (WidgetKit's on the Home Screen, the host's
    /// `widgetContainer` in the app).
    init(_ surface: CardSurface) {
        self.init(surface: surface, shape: ContainerRelativeShape())
    }
}

/// A Beacon rail's background: always the widget's own state colour. The opaque base keeps the
/// chosen body style from showing through the rail's soft gradient.
struct BeaconRailBackground: View {
    let fillARGB: UInt32
    /// The opacity the gradient fades to at its bottom-trailing corner.
    let fade: Double

    var body: some View {
        let fill = Color(argb: fillARGB)
        return LinearGradient(colors: [fill, fill.opacity(fade)], startPoint: .topLeading, endPoint: .bottomTrailing)
            // A plain rectangle. As a background *style* the base took the container's rounded
            // corners, so on a light body (Snow) the body showed at the rail's inner corners.
            .background { Rectangle().fill(Color(argb: BeaconSurfaceColors.graphiteARGB)) }
    }
}
