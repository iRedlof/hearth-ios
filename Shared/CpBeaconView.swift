import SwiftUI
import AppIntents
import HearthKit

/// The ChargePoint Beacon card, ported from the Android `ChargePointWidget`. Unlike the other widgets,
/// its rail is a FIXED brand orange. Left: the brand mark, the Auto-waitlist pill, and the hero "answer"
/// (plugs free / "Sign in" / "#3" / "Charging"); right: the site, account, plugs-free, and the action.
/// (Core states; the auto-run offer/accept machinery, live countdowns, and floor levels are deferred.)
public struct CpBeaconView: View {
    public let snap: CpSnapshot
    public init(_ snap: CpSnapshot) { self.snap = snap }

    private var fill: Color { Color(argb: snap.tone.fillARGB) }      // brand orange
    private var ink: Color { Color(argb: snap.tone.inkARGB) }        // dark brown (on orange)
    private var surfaceInk: Color { Color(argb: BeaconSurfaceColors.inkARGB) }

    public var body: some View {
        GeometryReader { geo in
            let s = beaconSplit(width: geo.size.width)   // Android rail is ~37%, not 50%
            HStack(spacing: 0) {
                left.frame(width: s.rail)
                right.frame(maxWidth: .infinity)
            }
        }
    }

    private var left: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 4) {
                Image("CpLogo").renderingMode(.template).resizable().scaledToFit()
                    .frame(width: 18, height: 18).foregroundStyle(ink)
                Spacer(minLength: 2)
                // Always-visible toggle for the auto-waitlist engine: filled dot = armed, hollow = off.
                Button(intent: CpControlIntent("autoToggle")) {
                    HStack(spacing: 4) {
                        Text("Auto").font(.system(size: 10, weight: .semibold))
                        Circle().fill(snap.autoOn ? ink : .clear)
                            .overlay(Circle().strokeBorder(ink, lineWidth: 1))
                            .frame(width: 7, height: 7)
                    }
                    .padding(.horizontal, 7).padding(.vertical, 3)
                    .background(ink.opacity(snap.autoOn ? 0.14 : 0.06), in: Capsule()).foregroundStyle(ink)
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 2)
            if let deadline = snap.deadline {
                // Timed states (offer / held): the countdown clock IS the hero, matching Android.
                Text(timerInterval: Date()...deadline, countsDown: true)
                    .font(.system(size: 34, weight: .heavy)).monospacedDigit().tracking(-0.5)
                    .foregroundStyle(ink).lineLimit(1).minimumScaleFactor(0.5)
                Text(snap.bigAnswer).font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(ink.opacity(0.9)).lineLimit(1).minimumScaleFactor(0.7)
                if !snap.sub.isEmpty {
                    Text(snap.sub).font(.system(size: 11)).foregroundStyle(ink.opacity(0.8))
                        .lineLimit(1).minimumScaleFactor(0.8)
                }
            } else {
                Text(snap.bigAnswer)
                    .font(.system(size: snap.bigAnswer.count > 6 ? 26 : 34, weight: .heavy)).tracking(-0.5)
                    .foregroundStyle(ink).lineLimit(1).minimumScaleFactor(0.6)
                if !snap.unit.isEmpty {
                    Text(snap.unit).font(.system(size: 12, weight: .medium)).foregroundStyle(ink.opacity(0.9)).lineLimit(1)
                }
                if !snap.sub.isEmpty {
                    Text(snap.sub).font(.system(size: 11)).foregroundStyle(ink.opacity(0.8))
                        .lineLimit(1).minimumScaleFactor(0.8).padding(.top, snap.unit.isEmpty ? 2 : 0)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 13).padding(.vertical, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(LinearGradient(colors: [fill, fill.opacity(0.85)], startPoint: .topLeading, endPoint: .bottomTrailing))
    }

    private var right: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(snap.site).font(.system(size: 18, weight: .bold)).foregroundStyle(surfaceInk).lineLimit(1).minimumScaleFactor(0.8)
            HStack(spacing: 4) {
                Image(systemName: "person.fill").font(.system(size: 10)).foregroundStyle(surfaceInk.opacity(0.7))
                Text(snap.account).font(.system(size: 12)).foregroundStyle(surfaceInk.opacity(0.85)).lineLimit(1).minimumScaleFactor(0.8)
            }.padding(.top, 2)
            Spacer(minLength: 4)
            detail
            Spacer(minLength: 6)
            if snap.keys.isEmpty { actionButton } else { keyRow }
        }
        .padding(.horizontal, 13).padding(.vertical, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(argb: BeaconSurfaceColors.graphiteARGB))
    }

    /// The middle detail: "Go to <charger>" when offered/held, else per-level floor stats when idle,
    /// else the aggregate plugs-free line (ports Android's CpRight.GoTo / Floors).
    @ViewBuilder private var detail: some View {
        if let goTo = snap.goTo {
            HStack(spacing: 5) {
                Image(systemName: "mappin.and.ellipse").font(.system(size: 11)).foregroundStyle(surfaceInk.opacity(0.8))
                Text("Go to \(goTo)").font(.system(size: 12.5, weight: .medium)).foregroundStyle(surfaceInk)
                    .lineLimit(1).minimumScaleFactor(0.8)
            }
        } else if !snap.floors.isEmpty {
            VStack(alignment: .leading, spacing: 3) {
                ForEach(snap.floors.prefix(4), id: \.level) { f in floorRow(f) }
            }
        } else if let plugs = snap.plugsFree {
            HStack(spacing: 5) {
                Image(systemName: "powerplug.fill").font(.system(size: 12)).foregroundStyle(surfaceInk.opacity(0.8))
                Text(plugs).font(.system(size: 12.5)).foregroundStyle(surfaceInk).lineLimit(1).minimumScaleFactor(0.8)
            }
        }
    }

    /// One parking level: label + a mini availability bar + "free/total".
    private func floorRow(_ f: CpFloor) -> some View {
        HStack(spacing: 6) {
            Text(f.level).font(.system(size: 11.5, weight: .semibold)).foregroundStyle(surfaceInk)
                .frame(width: 26, alignment: .leading)
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(surfaceInk.opacity(0.14))
                    Capsule().fill(fill)
                        .frame(width: f.total > 0 ? g.size.width * CGFloat(f.free) / CGFloat(f.total) : 0)
                }
            }.frame(height: 5)
            Text("\(f.free)/\(f.total)").font(.system(size: 11)).foregroundStyle(surfaceInk.opacity(0.85))
                .frame(width: 40, alignment: .trailing)
        }
    }

    /// "Open" deep-links to the ChargePoint app; "Sign in"/"Join" are plain (the card's default tap
    /// opens Hearth, where sign-in / join live).
    @ViewBuilder private var actionButton: some View {
        let label = Text(snap.actionLabel)
            .font(.system(size: 13, weight: .semibold)).foregroundStyle(Color(white: 0.12))
            .frame(maxWidth: .infinity).frame(height: 36)
            .background(fill, in: RoundedRectangle(cornerRadius: 11))
        if snap.actionLabel == "Open" {
            Link(destination: URL(string: "chargepoint://")!) { label }
        } else if snap.actionLabel == "Join" {
            Button(intent: CpJoinIntent()) { label }.buttonStyle(.plain)
        } else {
            label
        }
    }

    /// State-specific manual commands (Accept / Snooze / Leave / Rejoin) when the waitlist offers them.
    private var keyRow: some View {
        HStack(spacing: 6) {
            ForEach(snap.keys, id: \.command) { key in
                if key.command == "snooze" {   // snooze asks a length (10/30/60) via the app
                    Button(intent: CpSnoozeIntent()) { keyLabel(key.label) }.buttonStyle(.plain)
                } else {
                    Button(intent: CpCommandIntent(key.command)) { keyLabel(key.label) }.buttonStyle(.plain)
                }
            }
        }
    }

    private func keyLabel(_ text: String) -> some View {
        Text(text).font(.system(size: 12, weight: .semibold)).foregroundStyle(Color(white: 0.12))
            .frame(maxWidth: .infinity).frame(height: 36)
            .background(fill, in: RoundedRectangle(cornerRadius: 11))
    }
}
