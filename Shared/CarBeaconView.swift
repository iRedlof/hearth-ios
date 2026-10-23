import SwiftUI
import HearthKit

/// The Car Beacon card, ported from the Android `CarWidget` (v1.4.28): a two-tone card — a light
/// mint status panel on the left, a dark graphite panel on the right with the car image, charge bar,
/// and the single Open Tesla button. All right-panel text uses the bright header ink; Sentry-on is red.
public struct CarBeaconView: View {
    public let snap: CarSnapshot
    public init(_ snap: CarSnapshot) { self.snap = snap }

    private var fill: Color { Color(argb: snap.tone.fillARGB) }
    private var ink: Color { Color(argb: snap.tone.inkARGB) }                       // dark text on light mint
    private var surfaceInk: Color { Color(argb: BeaconSurfaceColors.inkARGB) }       // bright text on graphite
    private var sentryInk: Color { snap.sentry == .on ? Color(argb: BeaconSurfaceColors.sentryOnARGB) : surfaceInk }

    public var body: some View {
        HStack(spacing: 0) {
            left.frame(maxWidth: .infinity)
            right.frame(maxWidth: .infinity)
        }
    }

    // MARK: Left — light mint status panel
    private var left: some View {
        VStack(alignment: .leading, spacing: 0) {
            Image(systemName: "car.fill").font(.system(size: 13)).foregroundStyle(ink.opacity(0.9))
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                Text(snap.battery.map(String.init) ?? "—").font(.system(size: 34, weight: .heavy)).tracking(-1.2)
                Text("%").font(.system(size: 15, weight: .heavy))
            }.foregroundStyle(ink).padding(.top, 1)
            Text(snap.range).font(.system(size: 12, weight: .medium)).foregroundStyle(ink)
            Rectangle().fill(ink.opacity(0.26)).frame(height: 1).padding(.top, 4).padding(.bottom, 1)
            statusRow("Lock", snap.lock, snap.lockWarn)
            statusRow("Doors", snap.doors, snap.doorsWarn)
            statusRow("Cabin", snap.cabin, false)
            statusRow("Outside", snap.outside, false)
            statusRow("Tires", snap.tires, snap.tiresWarn)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12).padding(.vertical, 11)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(LinearGradient(colors: [fill, fill.opacity(0.9)], startPoint: .topLeading, endPoint: .bottomTrailing))
    }

    private func statusRow(_ key: String, _ value: String, _ warn: Bool) -> some View {
        HStack(spacing: 3) {
            Text(key).font(.system(size: 12)).foregroundStyle(ink.opacity(0.82)).lineLimit(1).minimumScaleFactor(0.8)
            Spacer(minLength: 2)
            Text(value).font(.system(size: 12.5, weight: warn ? .heavy : .bold)).foregroundStyle(ink)
                .underline(warn).lineLimit(1).minimumScaleFactor(0.8)
        }.padding(.vertical, 1.5)
    }

    // MARK: Right — dark graphite panel
    private var right: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 6) {
                Text(snap.name).font(.system(size: 18, weight: .bold)).foregroundStyle(surfaceInk).lineLimit(1)
                Spacer(minLength: 2)
                VStack(alignment: .trailing, spacing: -1) {
                    Text("Checked").font(.system(size: 10))
                    Text(snap.checkedAt).font(.system(size: 10))
                }.foregroundStyle(surfaceInk)
            }
            Text(snap.place).font(.system(size: 12.5)).foregroundStyle(surfaceInk)
                .lineLimit(1).minimumScaleFactor(0.72).padding(.top, 3)
            HStack(spacing: 4) {
                Image(systemName: "lock.shield.fill").font(.system(size: 11))
                Text(sentryText).font(.system(size: 12, weight: .medium))
            }.foregroundStyle(sentryInk).padding(.top, 2)
            Spacer(minLength: 2)
            Image("CarPremium").resizable().scaledToFit().frame(maxWidth: .infinity)
            Spacer(minLength: 2)
            chargeBar.frame(height: 7)
            Text(snap.chargeLine).font(.system(size: 12)).foregroundStyle(surfaceInk)
                .lineLimit(1).minimumScaleFactor(0.8).padding(.top, 3)
            Spacer(minLength: 4)
            openTesla
        }
        .padding(.horizontal, 13).padding(.vertical, 11)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(argb: BeaconSurfaceColors.graphiteARGB))
    }

    private var sentryText: String {
        switch snap.sentry { case .on: "Sentry on"; case .off: "Sentry off"; case .unknown: "Sentry —" }
    }

    private var chargeBar: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.13))
                Capsule()
                    .fill(Color(argb: snap.tone == .mint ? 0xFF8FF0C4 : snap.tone.fillARGB))
                    .frame(width: g.size.width * CGFloat(min(max(snap.battery ?? 0, 0), 100)) / 100)
                Rectangle().fill(surfaceInk).frame(width: 2).offset(x: g.size.width * 0.8 - 1)
            }
        }
    }

    private var openTesla: some View {
        HStack(spacing: 6) {
            Image(systemName: "arrow.right").font(.system(size: 13, weight: .semibold))
            Text("Open Tesla").font(.system(size: 13, weight: .semibold))
        }
        .foregroundStyle(surfaceInk)
        .frame(maxWidth: .infinity).frame(height: 36)
        .background(Color.white.opacity(0.11), in: RoundedRectangle(cornerRadius: 11))
    }
}
