import SwiftUI
import AppIntents
import HearthKit

/// The Lights card (`.systemLarge`): a dark surface with a tile grid — the on-lights, then an
/// "always show" pinned section. Each tile taps to toggle (`LightToggleIntent`). Ported from the
/// Android Lights widget (SwiftUI `LazyVGrid` replaces the Android grid math).
public struct LightTileView: View {
    public let snap: LightsSnapshot
    public init(_ snap: LightsSnapshot) { self.snap = snap }

    @Environment(\.cardStyle) private var cardStyle
    /// Status is this card's own graphite; a colour or black replaces it (Android `CardLook.kt`).
    private var look: CardLook { cardLook(cardStyle, warn: false, emergency: false) }
    private var textScale: CGFloat { look.textScale }
    private var ink: Color { look.inkColor(status: BeaconSurfaceColors.inkARGB) }
    /// A light that is on with no colour of its own.
    private var onAccent: Color { Color(argb: look.statusColours ? 0xFFFF_D27F : look.flag) }
    private let columns = [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)]
    private var page: LightTilePage { lightTilePage(snap.summary) }
    private var visiblePinned: [LightView] { page.pinned }
    private var visibleOn: [LightView] { page.main }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            if snap.state == .setup || snap.state == .loading || snap.state == .failed {
                TileStatusContent(state: snap.state, error: snap.error, choice: "", empty: "No lights found", ink: ink)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    if !visibleOn.isEmpty {
                        LazyVGrid(columns: columns, spacing: 8) { ForEach(visibleOn, id: \.id) { tile($0) } }
                    }
                    if !visiblePinned.isEmpty {
                        Text("ALWAYS SHOW").font(HearthFont.caption.font(scale: textScale).weight(.semibold)).tracking(0.5)
                            .foregroundStyle(ink.opacity(0.7)).padding(.top, 2)
                        LazyVGrid(columns: columns, spacing: 8) {
                            ForEach(visiblePinned, id: \.id) { tile($0) }
                        }
                    }
                    if snap.summary.on.isEmpty && snap.summary.pinned.isEmpty {
                        Text(snap.summary.offCount > 0 ? "\(snap.summary.offCount) off" : "No lights")
                            .font(HearthFont.groupLabel.font(scale: textScale)).foregroundStyle(ink.opacity(0.6)).padding(.top, 4)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                if page.hiddenCount > 0 {
                    TileMoreContent(count: page.hiddenCount, ink: ink)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .cardBackground(look) { Color(argb: BeaconSurfaceColors.graphiteARGB) }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(snap.state == .ready || snap.state == .empty ? snap.summary.headline : "Lights")
                .font(HearthFont.cardHeading.font(scale: textScale).weight(.bold)).foregroundStyle(ink)
                .lineLimit(1).minimumScaleFactor(0.7)
            Spacer()
            Button(intent: WidgetRefreshIntent("com.rohit.hearth.lights")) {
                Image(systemName: "arrow.clockwise").font(HearthFont.footnote.font.weight(.semibold)).foregroundStyle(ink.opacity(0.7))
            }.buttonStyle(.plain)
            if cardShowsCheckedStamp(smallPrint: look.smallPrint) {
                Text(snap.checkedAt).font(HearthFont.caption.font(scale: textScale)).foregroundStyle(ink.opacity(0.7))
                    .padding(.leading, 6).invalidatableContent()
            }
        }
    }

    private func tile(_ v: LightView) -> some View {
        let accent = v.rgb.map { Color(argb: $0) } ?? onAccent
        let label = VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Image(systemName: v.on ? "lightbulb.fill" : "lightbulb")
                        .font(HearthFont.rowTitle.font).foregroundStyle(v.on ? accent : ink.opacity(0.45))
                    Spacer()
                    if let p = v.percent { Text("\(p)%").font(HearthFont.caption.font(scale: textScale).weight(.semibold)).foregroundStyle(ink.opacity(0.7)) }
                }
                Spacer(minLength: 2)
                Text(v.name).font(HearthFont.callout.font(scale: textScale).weight(.semibold)).foregroundStyle(ink).lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Text(v.tile).font(HearthFont.footnote.font(scale: textScale)).foregroundStyle(ink.opacity(0.8)).lineLimit(1)
            }
            .padding(9).frame(maxWidth: .infinity, alignment: .topLeading).frame(height: 92)
            .background(v.on ? ink.opacity(0.13) : ink.opacity(0.05), in: RoundedRectangle(cornerRadius: 13))
        return Group {
            if v.available {
                Button(intent: LightToggleIntent(v.id, on: !v.on)) { label }.buttonStyle(.plain)
            } else {
                label.accessibilityLabel("\(v.name), Unavailable")
            }
        }
    }
}
