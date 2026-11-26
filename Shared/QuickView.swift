import SwiftUI
import AppIntents
import HearthKit

/// The Quick widget (`.systemMedium`): a grid of script keys; tap runs the script. Ported from the
/// Android Quick widget.
public struct QuickView: View {
    public let snap: QuickSnapshot
    public init(_ snap: QuickSnapshot) { self.snap = snap }

    private let ink = Color(argb: BeaconSurfaceColors.inkARGB)
    private let columns = [GridItem(.flexible(), spacing: 7), GridItem(.flexible(), spacing: 7)]

    public var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text("Quick").font(.system(size: 15, weight: .bold)).foregroundStyle(ink)
                Spacer()
                Button(intent: WidgetRefreshIntent("com.rohit.hearth.quick")) {
                    Image(systemName: "arrow.clockwise").font(.system(size: 11, weight: .semibold)).foregroundStyle(ink.opacity(0.7))
                }.buttonStyle(.plain)
            }
            if snap.keys.isEmpty {
                TileStatusContent(state: snap.state, error: snap.error, choice: "Choose your scripts",
                                  empty: "No scripts found")
            } else {
                LazyVGrid(columns: columns, spacing: 7) {
                    ForEach(snap.keys.prefix(4), id: \.id) { key($0) }
                }
                if let error = snap.error {
                    HStack(spacing: 6) {
                        Text(error).font(.system(size: 12)).foregroundStyle(ink.opacity(0.8)).lineLimit(1)
                        if snap.keys.count > 4 {
                            Spacer(minLength: 0)
                            TileMoreContent(count: snap.keys.count - 4)
                        }
                    }
                } else if snap.keys.count > 4 { TileMoreContent(count: snap.keys.count - 4) }
            }
            Spacer(minLength: 0)
        }
        .padding(13)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(argb: BeaconSurfaceColors.graphiteARGB))
    }

    private func key(_ k: QuickKey) -> some View {
        let label = HStack(spacing: 6) {
                Image(systemName: "play.circle.fill").font(.system(size: 14)).foregroundStyle(ink.opacity(0.85))
                VStack(alignment: .leading, spacing: 0) {
                    Text(k.name).font(.system(size: 13.5, weight: .semibold)).foregroundStyle(ink).lineLimit(1)
                    if !k.available {
                        Text("Unavailable").font(.system(size: 11)).foregroundStyle(ink.opacity(0.8)).lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10).frame(height: 38).frame(maxWidth: .infinity, alignment: .leading)
            .background(ink.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
        return Group {
            if k.available {
                Button(intent: QuickRunIntent(k.id)) { label }.buttonStyle(.plain)
            } else {
                label.accessibilityLabel("\(k.name), Unavailable")
            }
        }
    }
}
