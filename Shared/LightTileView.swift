import SwiftUI
import AppIntents
import HearthKit

/// The Lights card (`.systemLarge`): a dark surface with a tile grid — the on-lights, then an
/// "always show" pinned section. Each tile taps to toggle (`LightToggleIntent`). Ported from the
/// Android Lights widget (SwiftUI `LazyVGrid` replaces the Android grid math).
public struct LightTileView: View {
    public let snap: LightsSnapshot
    public init(_ snap: LightsSnapshot) { self.snap = snap }

    private let ink = Color(argb: BeaconSurfaceColors.inkARGB)
    private let columns = [GridItem(.adaptive(minimum: 96), spacing: 8)]

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            if !snap.summary.on.isEmpty {
                LazyVGrid(columns: columns, spacing: 8) { ForEach(snap.summary.on, id: \.id) { tile($0) } }
            }
            if !snap.summary.pinned.isEmpty {
                Text("ALWAYS SHOW").font(.system(size: 9, weight: .semibold)).tracking(0.5)
                    .foregroundStyle(ink.opacity(0.45)).padding(.top, 2)
                LazyVGrid(columns: columns, spacing: 8) { ForEach(snap.summary.pinned, id: \.id) { tile($0) } }
            }
            if snap.summary.on.isEmpty && snap.summary.pinned.isEmpty {
                Text(snap.summary.offCount > 0 ? "\(snap.summary.offCount) off" : "No lights")
                    .font(.system(size: 13)).foregroundStyle(ink.opacity(0.6)).padding(.top, 4)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(argb: BeaconSurfaceColors.graphiteARGB))
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(snap.summary.headline).font(.system(size: 18, weight: .bold)).foregroundStyle(ink)
                .lineLimit(1).minimumScaleFactor(0.7)
            Spacer()
            Button(intent: WidgetRefreshIntent("com.rohit.hearth.lights")) {
                Image(systemName: "arrow.clockwise").font(.system(size: 12, weight: .semibold)).foregroundStyle(ink.opacity(0.7))
            }.buttonStyle(.plain)
            Text(snap.checkedAt).font(.system(size: 10)).foregroundStyle(ink.opacity(0.7)).padding(.leading, 6)
        }
    }

    private func tile(_ v: LightView) -> some View {
        let accent = v.rgb.map { Color(argb: $0) } ?? Color(argb: 0xFFFF_D27F)
        return Button(intent: LightToggleIntent(v.id, on: !v.on)) {
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Image(systemName: v.on ? "lightbulb.fill" : "lightbulb")
                        .font(.system(size: 15)).foregroundStyle(v.on ? accent : ink.opacity(0.45))
                    Spacer()
                    if let p = v.percent { Text("\(p)%").font(.system(size: 10, weight: .semibold)).foregroundStyle(ink.opacity(0.7)) }
                }
                Spacer(minLength: 2)
                Text(v.name).font(.system(size: 11.5, weight: .medium)).foregroundStyle(ink).lineLimit(1).minimumScaleFactor(0.8)
                Text(v.tile).font(.system(size: 9)).foregroundStyle(ink.opacity(0.6)).lineLimit(1)
            }
            .padding(9).frame(maxWidth: .infinity, minHeight: 64, alignment: .topLeading)
            .background(v.on ? ink.opacity(0.13) : ink.opacity(0.05), in: RoundedRectangle(cornerRadius: 13))
        }.buttonStyle(.plain)
    }
}
