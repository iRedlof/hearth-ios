import SwiftUI
import AppIntents
import HearthKit

/// The Favourites card (`.systemLarge`): a tile grid of pinned entities across switch / light / fan /
/// input_boolean / script; each tap toggles (or runs). Ported from the Android Favourites widget.
public struct FavouritesView: View {
    public let snap: FavSnapshot
    public init(_ snap: FavSnapshot) { self.snap = snap }

    private let ink = Color(argb: BeaconSurfaceColors.inkARGB)
    private let columns = [GridItem(.adaptive(minimum: 96), spacing: 8)]

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("Favourites").font(.system(size: 18, weight: .bold)).foregroundStyle(ink)
                Spacer()
                Button(intent: WidgetRefreshIntent("com.rohit.hearth.favourites")) {
                    Image(systemName: "arrow.clockwise").font(.system(size: 12, weight: .semibold)).foregroundStyle(ink.opacity(0.7))
                }.buttonStyle(.plain)
                Text(snap.checkedAt).font(.system(size: 10)).foregroundStyle(ink.opacity(0.7)).padding(.leading, 6).invalidatableContent()
            }
            if snap.items.isEmpty {
                Text("No favourites chosen").font(.system(size: 13)).foregroundStyle(ink.opacity(0.6)).padding(.top, 4)
            } else {
                LazyVGrid(columns: columns, spacing: 8) { ForEach(snap.items, id: \.id) { tile($0) } }
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(argb: BeaconSurfaceColors.graphiteARGB))
    }

    private func tile(_ f: Fav) -> some View {
        Button(intent: FavToggleIntent(f.id, on: !f.on)) {
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Image(systemName: icon(f.domain)).font(.system(size: 15))
                        .foregroundStyle(f.on ? Color(argb: 0xFFFF_D27F) : ink.opacity(0.45))
                    Spacer()
                }
                Spacer(minLength: 2)
                Text(f.name).font(.system(size: 11.5, weight: .medium)).foregroundStyle(ink).lineLimit(1).minimumScaleFactor(0.8)
                Text(f.domain == "script" ? "Run" : (f.on ? "On" : "Off")).font(.system(size: 9)).foregroundStyle(ink.opacity(0.6))
            }
            .padding(9).frame(maxWidth: .infinity, minHeight: 64, alignment: .topLeading)
            .background(f.on ? ink.opacity(0.13) : ink.opacity(0.05), in: RoundedRectangle(cornerRadius: 13))
        }.buttonStyle(.plain)
    }

    private func icon(_ domain: String) -> String {
        switch domain {
        case "light": "lightbulb.fill"
        case "fan": "fanblades.fill"
        case "input_boolean": "switch.2"
        case "script": "play.circle.fill"
        default: "power"   // switch
        }
    }
}
