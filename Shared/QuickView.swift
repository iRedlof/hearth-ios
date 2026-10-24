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
                Text("No scripts chosen").font(.system(size: 12)).foregroundStyle(ink.opacity(0.6))
            } else {
                LazyVGrid(columns: columns, spacing: 7) {
                    ForEach(snap.keys.prefix(6), id: \.id) { key($0) }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(13)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(argb: BeaconSurfaceColors.graphiteARGB))
    }

    private func key(_ k: QuickKey) -> some View {
        Button(intent: QuickRunIntent(k.id)) {
            HStack(spacing: 6) {
                Image(systemName: "play.circle.fill").font(.system(size: 14)).foregroundStyle(ink.opacity(0.85))
                Text(k.name).font(.system(size: 12.5, weight: .medium)).foregroundStyle(ink).lineLimit(1).minimumScaleFactor(0.8)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10).frame(height: 38).frame(maxWidth: .infinity, alignment: .leading)
            .background(ink.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
        }.buttonStyle(.plain)
    }
}
