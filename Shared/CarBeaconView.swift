import SwiftUI
import AppIntents
import HearthKit

/// Inert samples retain the same labels without constructing executable controls.
public enum CarInteractionMode {
    case live, inert
}

/// The Car Beacon card, ported from the Android `CarWidget` (v1.4.28): a two-tone card — a light
/// mint status panel on the left, a dark graphite panel on the right with the car image, charge bar,
/// and the single Open Tesla button. All right-panel text uses the bright header ink; Sentry-on is red.
public struct CarBeaconView: View {
    public let snap: CarSnapshot
    public let interactionMode: CarInteractionMode
    public init(_ snap: CarSnapshot, interactionMode: CarInteractionMode = .live) {
        self.snap = snap
        self.interactionMode = interactionMode
    }

    private var fill: Color { Color(argb: snap.tone.fillARGB) }
    private var ink: Color { Color(argb: snap.tone.inkARGB) }                       // dark text on light mint
    private var surfaceInk: Color { Color(argb: BeaconSurfaceColors.inkARGB) }       // bright text on graphite
    private var sentryInk: Color { snap.sentry == .on && !snap.stale ? Color(argb: BeaconSurfaceColors.sentryOnARGB) : surfaceInk }

    public var body: some View {
        GeometryReader { geo in
            let s = beaconSplit(width: geo.size.width)   // Android rail is ~37%, not 50%
            let compact = geo.size.height < 165
            HStack(alignment: .top, spacing: 0) {
                left(compact: compact)
                    .frame(width: s.rail, height: geo.size.height, alignment: .topLeading)
                right(compact: compact)
                    .frame(width: geo.size.width - s.rail, height: geo.size.height, alignment: .topLeading)
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
        }
    }

    // MARK: Left — light mint status panel
    private func left(compact: Bool) -> some View {
        // At 155pt: 41 hero + 15 range + 3 divider + 5×16 readings + 14 padding = 153pt.
        let rowHeight: CGFloat = compact ? 16 : 17
        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 0) {
                    Text(snap.battery.map(String.init) ?? "—").font(.system(size: 34, weight: .heavy)).tracking(-1.2)
                    if snap.battery != nil { Text("%").font(.system(size: 15, weight: .heavy)) }
                }
                Spacer(minLength: 0)
                Image(systemName: "car.fill").font(.system(size: 13)).foregroundStyle(ink.opacity(0.9))
            }
            .foregroundStyle(ink).frame(height: 41, alignment: .leading)
            Text(snap.range).font(.system(size: 12, weight: .medium)).foregroundStyle(ink)
                .lineLimit(1).frame(height: compact ? 15 : 16, alignment: .leading)
            Rectangle().fill(ink.opacity(0.26)).frame(height: 1)
                .padding(.vertical, compact ? 1 : 2)
            statusRow("Lock", snap.lock, snap.lockWarn, height: rowHeight)
            statusRow("Doors", snap.doors, snap.doorsWarn, height: rowHeight)
            statusRow("Cabin", snap.cabin, false, height: rowHeight)
            statusRow("Outside", snap.outside, false, height: rowHeight)
            statusRow("Tires", snap.tires, snap.tiresWarn, height: rowHeight)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12).padding(.vertical, compact ? 7 : 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(LinearGradient(colors: [fill, fill.opacity(0.9)], startPoint: .topLeading, endPoint: .bottomTrailing))
    }

    private func statusRow(_ key: String, _ value: String, _ warn: Bool, height: CGFloat) -> some View {
        HStack(spacing: 1) {
            Text(key).font(.system(size: 13)).foregroundStyle(ink.opacity(0.82)).lineLimit(1)
            Spacer(minLength: 0)
            Text(value).font(.system(size: 13, weight: warn ? .heavy : .bold)).foregroundStyle(ink)
                .underline(warn).lineLimit(1).minimumScaleFactor(0.9)
        }.frame(height: height)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(key), \(value)")
    }

    // MARK: Right — dark graphite panel
    private func right(compact: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 6) {
                Text(snap.name).font(.system(size: 18, weight: .bold)).foregroundStyle(surfaceInk).lineLimit(1)
                Spacer(minLength: 2)
                BeaconFreshness(checkedAt: snap.checkedAt, kind: "com.rohit.hearth.car",
                    ink: surfaceInk, interactionsEnabled: interactionMode == .live)
            }
            .frame(height: 26, alignment: .top)
            Text(snap.place).font(.system(size: 12.5)).foregroundStyle(surfaceInk)
                .lineLimit(1).minimumScaleFactor(0.72).frame(height: 15, alignment: .leading).padding(.top, 2)
            // The photo takes the remaining height; readings and the footer retain their own rows.
            Image("CarPremium").resizable().scaledToFit()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .layoutPriority(-1)
            chargeBar.frame(height: 7)
            // Unplugged (left) + Sentry on/off (right-aligned) share one line — frees a row for the photo.
            HStack(spacing: 6) {
                Text(snap.chargeLine).font(.system(size: 12)).foregroundStyle(surfaceInk)
                    .lineLimit(1).minimumScaleFactor(0.8)
                    .accessibilityLabel(snap.error ?? snap.chargeLine)
                Spacer(minLength: 4)
                HStack(spacing: 4) {
                    Image(systemName: "lock.shield.fill").font(.system(size: 10.5))
                    Text(sentryText).font(.system(size: 12, weight: .medium))
                }.foregroundStyle(sentryInk).lineLimit(1).minimumScaleFactor(0.85).fixedSize()
            }.frame(height: 16).padding(.top, 3)
            openTesla.padding(.top, 5)
        }
        .padding(.horizontal, 13).padding(.top, compact ? 8 : 10).padding(.bottom, 6)
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
                if let limit = snap.limit {
                    Rectangle().fill(surfaceInk).frame(width: 2)
                        .offset(x: max(0, min(g.size.width - 2,
                            g.size.width * CGFloat(min(max(limit, 0), 100)) / 100 - 1)))
                }
            }
        }
    }

    @ViewBuilder private var openTesla: some View {
        if interactionMode == .inert {
            actionLabel(snap.needsSettings
                ? (snap.needsSignIn ? "Sign in" : "Open Settings") : "Open Tesla")
        } else if snap.needsSettings {
            Button(intent: HaSetupIntent(reconnect: snap.needsSignIn)) {
                actionLabel(snap.needsSignIn ? "Sign in" : "Open Settings")
            }.buttonStyle(.plain)
        } else {
            // Deep-links to the Tesla app. The whole card otherwise opens Hearth.
            Link(destination: URL(string: "tesla://")!) { actionLabel("Open Tesla") }
        }
    }

    private func actionLabel(_ title: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "arrow.right").font(.system(size: 13, weight: .semibold))
            Text(title).font(.system(size: 13, weight: .semibold))
        }
            .foregroundStyle(surfaceInk)
            .frame(maxWidth: .infinity).frame(height: 36)
            .background(Color.white.opacity(0.11), in: RoundedRectangle(cornerRadius: 11))
    }
}
