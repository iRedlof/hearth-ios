import SwiftUI
import HearthKit

/// The three background choices as swatch tiles: Status, Colour, Black (`BackgroundChoices` in
/// Android's `CardStylePage.kt`, without Glass and Wallpaper).
struct CardBackgroundTiles: View {
    let current: CardBackground
    let onPick: (CardBackground) -> Void
    @Environment(\.colorScheme) private var scheme

    private enum Tile {
        static let side: CGFloat = 48
        static let corner: CGFloat = 16
        static let border: CGFloat = 2
        static let labelGap: CGFloat = 6
        /// Under every swatch, as on Android.
        static let baseARGB: UInt32 = 0xFF3A3330
        /// Calm, needs you, urgent: what "Status" means.
        static let statusARGB: [UInt32] = [0xFF1E8C66, 0xFFD9961F, 0xFFE5463D]
        static let blackARGB: UInt32 = 0xFF000000
    }

    /// The colour the Colour tile shows and picks: the chosen one, else the first.
    private var colour: CardColour {
        if case .colour(let chosen) = current { chosen } else { CardColour.allCases[0] }
    }

    var body: some View {
        HStack(spacing: 0) {
            tile("Status", .status, selected: current == .status) {
                LinearGradient(colors: Tile.statusARGB.map(Color.init(argb:)),
                               startPoint: .topLeading, endPoint: .bottomTrailing)
            }
            tile("Colour", .colour(colour), selected: current == .colour(colour)) {
                LinearGradient(colors: [Color(argb: colour.topARGB), Color(argb: colour.bottomARGB)],
                               startPoint: .top, endPoint: .bottom)
            }
            tile("Black", .black, selected: current == .black) { Color(argb: Tile.blackARGB) }
        }
        .padding(.horizontal, HearthMetrics.rowSidePadding)
        .padding(.vertical, HearthMetrics.mediumPadding)
    }

    private func tile<Swatch: View>(_ label: String, _ background: CardBackground, selected: Bool,
                                    @ViewBuilder swatch: () -> Swatch) -> some View {
        let shape = RoundedRectangle(cornerRadius: Tile.corner, style: .continuous)
        let swatchView = swatch()
        return Button {
            onPick(background)
        } label: {
            VStack(spacing: Tile.labelGap) {
                swatchView
                    .frame(width: Tile.side, height: Tile.side)
                    .background(Color(argb: Tile.baseARGB))
                    .clipShape(shape)
                    .overlay(shape.strokeBorder(selected ? HearthColor.ink(scheme) : .clear, lineWidth: Tile.border))
                Text(label)
                    .font(HearthFont.groupLabel.font)
                    .foregroundStyle(selected ? HearthColor.ink(scheme) : HearthColor.sub(scheme))
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// The eight colours as round swatches in Android's order, the chosen one named underneath.
struct CardColourSwatches: View {
    let current: CardColour
    let onPick: (CardColour) -> Void
    @Environment(\.colorScheme) private var scheme

    private enum Swatch {
        static let side: CGFloat = 32
        static let border: CGFloat = 2
        static let nameGap: CGFloat = 8
    }

    var body: some View {
        VStack(spacing: Swatch.nameGap) {
            HStack(spacing: 0) {
                ForEach(CardColour.allCases, id: \.self) { colour in swatch(colour) }
            }
            Text(current.label)
                .font(HearthFont.subtitle.font)
                .foregroundStyle(HearthColor.sub(scheme))
                .accessibilityHidden(true)
        }
        .padding(.horizontal, HearthMetrics.rowSidePadding)
        .padding(.vertical, HearthMetrics.mediumPadding)
    }

    private func swatch(_ colour: CardColour) -> some View {
        let selected = colour == current
        return Button {
            onPick(colour)
        } label: {
            LinearGradient(colors: [Color(argb: colour.topARGB), Color(argb: colour.bottomARGB)],
                           startPoint: .top, endPoint: .bottom)
                .frame(width: Swatch.side, height: Swatch.side)
                .clipShape(Circle())
                .overlay(Circle().strokeBorder(selected ? HearthColor.ink(scheme) : .clear, lineWidth: Swatch.border))
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(colour.label)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// The All-cards preview's ‹ name › stepper across the added widgets.
struct CardStylePreviewStepper: View {
    let name: String
    let onStep: (Int) -> Void
    @Environment(\.colorScheme) private var scheme

    private enum Stepper {
        static let button: CGFloat = 40
        static let nameWidth: CGFloat = 150
    }

    var body: some View {
        HStack(spacing: HearthMetrics.smallPadding) {
            arrow("chevron.left", label: "Previous widget", step: -1)
            Text(name)
                .font(HearthFont.rowTitle.font.weight(.semibold))
                .foregroundStyle(HearthColor.ink(scheme))
                .lineLimit(1)
                .frame(width: Stepper.nameWidth)
            arrow("chevron.right", label: "Next widget", step: 1)
        }
        .frame(maxWidth: .infinity)
    }

    private func arrow(_ symbol: String, label: String, step: Int) -> some View {
        Button {
            onStep(step)
        } label: {
            Image(systemName: symbol)
                .font(HearthFont.callout.font.weight(.semibold))
                .foregroundStyle(HearthColor.ink(scheme))
                .frame(width: Stepper.button, height: Stepper.button)
                .background(HearthColor.tint(scheme), in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}
