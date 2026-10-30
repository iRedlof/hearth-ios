import SwiftUI
import AppIntents
import HearthKit

/// The Favourites card (`.systemLarge`): a tile grid of pinned entities across switch / light / fan /
/// input_boolean / script; each tap toggles (or runs). Ported from the Android Favourites widget.
public struct FavouritesView: View {
    public let snap: FavSnapshot
    public init(_ snap: FavSnapshot) { self.snap = snap }

    private let ink = Color(argb: BeaconSurfaceColors.inkARGB)
    private let columns = [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)]

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
                TileStatusContent(state: snap.state, error: snap.error, choice: "Choose your favourites",
                                  empty: "No favourites found")
            } else {
                if let error = snap.error {
                    Text(error).font(.system(size: 12)).foregroundStyle(ink.opacity(0.8)).lineLimit(1)
                }
                LazyVGrid(columns: columns, spacing: 8) { ForEach(snap.items.prefix(4), id: \.id) { tile($0) } }
                if snap.items.count > 4 { TileMoreContent(count: snap.items.count - 4) }
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(argb: BeaconSurfaceColors.graphiteARGB))
    }

    private func tile(_ f: Fav) -> some View {
        let label = VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Image(systemName: icon(f.domain)).font(.system(size: 15))
                        .foregroundStyle(f.on ? Color(argb: 0xFFFF_D27F) : ink.opacity(0.45))
                    Spacer()
                }
                Spacer(minLength: 2)
                Text(f.name).font(.system(size: 14, weight: .semibold)).foregroundStyle(ink).lineLimit(2)
                Text(!f.available ? "Unavailable" : f.domain == "script" ? "Run" : (f.on ? "On" : "Off"))
                    .font(.system(size: 12)).foregroundStyle(ink.opacity(0.8))
            }
            .padding(9).frame(maxWidth: .infinity, alignment: .topLeading).frame(height: 92)
            .background(f.on ? ink.opacity(0.13) : ink.opacity(0.05), in: RoundedRectangle(cornerRadius: 13))
        return Group {
            if f.available {
                Button(intent: FavToggleIntent(f.id, turnOn: f.requestedOn)) { label }.buttonStyle(.plain)
            } else {
                label.accessibilityLabel("\(f.name), Unavailable")
            }
        }
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
