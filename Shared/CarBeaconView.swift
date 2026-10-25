import SwiftUI
import AppIntents
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
        GeometryReader { geo in
            let s = beaconSplit(width: geo.size.width)   // Android rail is ~37%, not 50%
            HStack(spacing: 0) {
                left.frame(width: s.rail)
                right.frame(maxWidth: .infinity)
            }
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
                BeaconFreshness(checkedAt: snap.checkedAt, kind: "com.rohit.hearth.car", ink: surfaceInk)
            }
            Text(snap.place).font(.system(size: 12.5)).foregroundStyle(surfaceInk)
                .lineLimit(1).minimumScaleFactor(0.72).padding(.top, 3)
            // Car photo — enlarged to fill the space freed by moving Sentry onto the charge line.
            Image("CarPremium").resizable().scaledToFit()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, -4).padding(.vertical, 3)
            chargeBar.frame(height: 7)
            // Unplugged (left) + Sentry on/off (right-aligned) share one line — frees a row for the photo.
            HStack(spacing: 6) {
                Text(snap.chargeLine).font(.system(size: 12)).foregroundStyle(surfaceInk)
                    .lineLimit(1).minimumScaleFactor(0.8)
                Spacer(minLength: 4)
                HStack(spacing: 4) {
                    Image(systemName: "lock.shield.fill").font(.system(size: 10.5))
                    Text(sentryText).font(.system(size: 12, weight: .medium))
                }.foregroundStyle(sentryInk).lineLimit(1).minimumScaleFactor(0.85).fixedSize()
            }.padding(.top, 3)
            openTesla.padding(.top, 6)
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
        // Deep-links to the Tesla app. iOS (unlike Android's package launch) can't detect whether
        // Tesla is installed, so there's no "Tesla unavailable" disabled state — if it's absent the
        // tap is a no-op. The whole card otherwise opens Hearth.
        Link(destination: URL(string: "tesla://")!) {
            HStack(spacing: 6) {
                Image(systemName: "arrow.right").font(.system(size: 13, weight: .semibold))
                Text("Open Tesla").font(.system(size: 13, weight: .semibold))
            }
            .foregroundStyle(surfaceInk)
            .frame(maxWidth: .infinity).frame(height: 36)
            .background(Color.white.opacity(0.11), in: RoundedRectangle(cornerRadius: 11))
        }
    }
}
