import SwiftUI
import AppIntents
import HearthKit

/// The ChargePoint Beacon card, ported from the Android `ChargePointWidget`. Unlike the other widgets,
/// its rail is a FIXED brand orange. Left: the brand mark, the Auto-waitlist pill, and the hero "answer"
/// (plugs free / "Sign in" / "#3" / "Charging"); right: the site, account, plugs-free, and the action.
/// Uses the production snapshot mapper for state-specific commands, countdowns and Auto controls.
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
                right(height: geo.size.height).frame(maxWidth: .infinity)
            }
        }
    }

    private var left: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 4) {
                Image("CpLogo").renderingMode(.template).resizable().scaledToFit()
                    .frame(width: 18, height: 18).foregroundStyle(ink)
                Spacer(minLength: 2)
                autoPill
            }
            Spacer(minLength: 2)
            if let deadline = snap.deadline {
                // Timed states (offer / held): the countdown clock IS the hero, matching Android.
                Group {
                    if let interval = cpCountdownInterval(until: deadline) {
                        Text(timerInterval: interval, countsDown: true)
                    } else {
                        Text("0:00")
                    }
                }
                .font(.system(size: 34, weight: .heavy)).monospacedDigit().tracking(-0.5)
                .foregroundStyle(ink).lineLimit(1).minimumScaleFactor(0.5)
                Text(snap.unit.isEmpty ? snap.bigAnswer : snap.unit).font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(ink.opacity(0.9)).lineLimit(1).minimumScaleFactor(0.7)
                if !snap.sub.isEmpty {
                    Text(snap.sub).font(.system(size: 11)).foregroundStyle(ink.opacity(0.8))
                        .lineLimit(2).minimumScaleFactor(0.85)
                        .accessibilityLabel(snap.statusDescription ?? snap.sub)
                }
                ForEach(snap.railNotes, id: \.self) { note in
                    Text(note).font(.system(size: 11)).foregroundStyle(ink.opacity(0.8)).lineLimit(1).minimumScaleFactor(0.8)
                }
            } else {
                // Android parity: a large plug-count hero + the "of 86 plugs / 7 in use / 1 offline" detail.
                Text(snap.bigAnswer)
                    .font(.system(size: snap.bigAnswer.count > 6 ? 30 : 48, weight: .heavy)).tracking(-1)
                    .foregroundStyle(ink).lineLimit(1).minimumScaleFactor(0.5)
                if !snap.unit.isEmpty {
                    Text(snap.unit).font(.system(size: 15, weight: .semibold)).foregroundStyle(ink).lineLimit(1).minimumScaleFactor(0.8)
                }
                ForEach(snap.freeDetail, id: \.self) { line in
                    Text(line).font(.system(size: 11)).foregroundStyle(ink.opacity(0.78)).lineLimit(1).minimumScaleFactor(0.8)
                }
                if !snap.sub.isEmpty {
                    Text(snap.sub).font(.system(size: 11)).foregroundStyle(ink.opacity(0.8))
                        .lineLimit(2).minimumScaleFactor(0.8).padding(.top, snap.unit.isEmpty ? 2 : 0)
                        .accessibilityLabel(snap.statusDescription ?? snap.sub)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 13).padding(.vertical, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(LinearGradient(colors: [fill, fill.opacity(0.85)], startPoint: .topLeading, endPoint: .bottomTrailing))
    }

    private var autoLabel: some View {
        HStack(spacing: 5) {
            Text("Auto").font(.system(size: 12, weight: .bold))
            Circle().fill(Color(argb: snap.autoOn ? 0xFF34C759 : 0xFF626A63))
                .overlay(Circle().strokeBorder(ink.opacity(0.45), lineWidth: 0.7))
                .frame(width: 8, height: 8)
        }
        .foregroundStyle(ink).frame(width: 62, height: 22)
        .background(ink.opacity(0.08), in: Capsule())
        .overlay(Capsule().strokeBorder(ink.opacity(0.23), lineWidth: 1))
    }

    @ViewBuilder private var autoPill: some View {
        if snap.autoControl == .disabled || (snap.working && !snap.autoOn) || (snap.origin == nil && snap.autoControl != .signin) {
            autoLabel.accessibilityLabel(snap.origin == nil && snap.account == "Unavailable"
                ? "Auto status unavailable" : snap.autoOn ? "Auto on. Command in progress" : "Auto off. Unavailable")
        } else if snap.autoControl == .signin {
            Button(intent: CpSetupIntent("signin")) { autoLabel }
                .buttonStyle(.plain).accessibilityLabel("Auto off. Sign in to start Auto")
        } else {
            Button(intent: CpControlIntent(snap.autoControl == .stop ? "pause" : snap.autoControl == .join ? "join" : "resume",
                                          origin: CpSessionStore.encodedActionOrigin(snap.origin))) { autoLabel }
                .buttonStyle(.plain)
                .accessibilityLabel(snap.autoOn ? "Auto on. Stop Auto" :
                    snap.autoControl == .join ? "Auto off. Join and start Auto" : "Auto off. Resume Auto")
        }
    }

    private func right(height: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // Android parity: site + account on the left, the refresh + "Checked" stamp on the right.
            HStack(alignment: .top, spacing: 6) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(snap.site).font(.system(size: 18, weight: .bold)).foregroundStyle(surfaceInk).lineLimit(1).minimumScaleFactor(0.8)
                    HStack(spacing: 4) {
                        Image(systemName: "person.fill").font(.system(size: 10)).foregroundStyle(surfaceInk.opacity(0.7))
                        Text(snap.account).font(.system(size: 12)).foregroundStyle(surfaceInk.opacity(0.85)).lineLimit(1).minimumScaleFactor(0.8)
                    }
                }
                Spacer(minLength: 2)
                if !snap.checkedAt.isEmpty {
                    BeaconFreshness(checkedAt: snap.checkedAt, kind: "com.rohit.hearth.chargepoint", ink: surfaceInk)
                }
            }
            Spacer(minLength: 2)
            detail
            Spacer(minLength: 2)
            if snap.keys.isEmpty {
                if snap.showOpen { HStack(spacing: 6) { actionButton; openKey } } else { actionButton }
            } else { keyRow }
        }
        .padding(.horizontal, 13).padding(.top, height < 222 ? 8 : 14).padding(.bottom, 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(argb: BeaconSurfaceColors.graphiteARGB))
    }

    /// A narrow "Open" key beside the primary action, deep-linking to ChargePoint (Android idle parity).
    private var openKey: some View {
        Link(destination: URL(string: "chargepoint://")!) {
            Text("Open").font(.system(size: 13, weight: .semibold)).foregroundStyle(surfaceInk)
                .padding(.horizontal, 16).frame(height: 36)
                .background(Color.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 11))
        }
    }

    /// The middle detail: "Go to <charger>" when offered/held, else per-level floor stats when idle,
    /// else the aggregate plugs-free line (ports Android's CpRight.GoTo / Floors).
    @ViewBuilder private var detail: some View {
        if let goTo = snap.goTo {
            if let level = cpLevelOf(goTo) {
                ViewThatFits(in: .vertical) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Go to level").font(.system(size: 13)).foregroundStyle(surfaceInk.opacity(0.7))
                        Text(level).font(.system(size: 34, weight: .heavy))
                            .foregroundStyle(fill).lineLimit(1)
                        Text(cpChargerShort(goTo)).font(.system(size: 14, weight: .bold))
                            .foregroundStyle(surfaceInk).lineLimit(1).minimumScaleFactor(0.85)
                    }
                    HStack(spacing: 8) {
                        Text(level).font(.system(size: 26, weight: .heavy)).foregroundStyle(fill)
                        Text(cpChargerShort(goTo)).font(.system(size: 14, weight: .bold))
                            .foregroundStyle(surfaceInk).lineLimit(1).minimumScaleFactor(0.85)
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Go to charger").font(.system(size: 13)).foregroundStyle(surfaceInk.opacity(0.7))
                    Text(cpChargerShort(goTo)).font(.system(size: 16, weight: .bold))
                        .foregroundStyle(surfaceInk).lineLimit(2).minimumScaleFactor(0.85)
                }
            }
        } else if !snap.stats.isEmpty {
            // Charging: the right panel carries Est. distance / Time elapsed / Charger rows (Android parity).
            VStack(alignment: .leading, spacing: 4) {
                ForEach(snap.stats, id: \.label) { s in
                    HStack(spacing: 4) {
                        Text(s.label).font(.system(size: 11.5)).foregroundStyle(surfaceInk.opacity(0.7))
                        Spacer(minLength: 4)
                        Text(s.value).font(.system(size: 12.5, weight: .semibold)).foregroundStyle(surfaceInk).lineLimit(1).minimumScaleFactor(0.8)
                    }
                }
            }
        } else if !snap.floors.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(snap.floors.prefix(5), id: \.level) { f in floorRow(f) }
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
                        .frame(width: f.total > 0 ? g.size.width * CGFloat(min(max(f.free, 0), f.total)) / CGFloat(f.total) : 0)
                }
            }.frame(height: 5)
            Text("\(f.free)/\(f.total)").font(.system(size: 11)).foregroundStyle(surfaceInk.opacity(0.85))
                .frame(width: 40, alignment: .trailing)
        }
    }

    /// "Open" deep-links to the ChargePoint app; "Sign in"/"Join" are plain (the card's default tap
    /// opens Hearth, where sign-in / join live).
    @ViewBuilder private var actionButton: some View {
        let label = Text(snap.actionLabel == "Open" ? "Open ChargePoint" : snap.actionLabel)
            .font(.system(size: 13, weight: .semibold)).foregroundStyle(Color(white: 0.12))
            .frame(maxWidth: .infinity).frame(height: 36)
            .background(fill, in: RoundedRectangle(cornerRadius: 11))
        if snap.bigAnswer == "Set up" {
            Button(intent: CpSetupIntent("location")) { label }.buttonStyle(.plain)
        } else if snap.actionLabel == "Open" {
            Link(destination: URL(string: "chargepoint://")!) { label }
        } else if snap.actionLabel == "Join" {
            Button(intent: CpJoinIntent(origin: CpSessionStore.encodedActionOrigin(snap.origin))) { label }.buttonStyle(.plain)
                .disabled(snap.working || snap.stale || snap.origin == nil)
        } else if snap.actionLabel == "Sign in" {
            Button(intent: CpSetupIntent("signin")) { label }.buttonStyle(.plain)
        } else {
            label
        }
    }

    /// State-specific manual commands (Accept / Snooze / Leave / Rejoin) when the waitlist offers them.
    private var keyRow: some View {
        HStack(spacing: 6) {
            ForEach(snap.keys, id: \.command) { key in
                if key.command == "open" {
                    Link(destination: URL(string: "chargepoint://")!) { keyLabel(key.label) }
                } else if key.command == "snooze" {
                    Button(intent: CpSnoozeIntent(origin: CpSessionStore.encodedActionOrigin(snap.origin))) { keyLabel(key.label) }.buttonStyle(.plain)
                        .disabled(snap.working || snap.stale || snap.origin == nil)
                } else {
                    Button(intent: CpCommandIntent(key.command, origin: CpSessionStore.encodedActionOrigin(snap.origin))) { keyLabel(key.label) }.buttonStyle(.plain)
                        .disabled(snap.working || snap.stale || snap.origin == nil)
                }
            }
        }
    }

    private func keyLabel(_ text: String) -> some View {
        Text(text).font(.system(size: 14, weight: .semibold)).foregroundStyle(Color(white: 0.12))
            .multilineTextAlignment(.center).lineLimit(2)
            .frame(maxWidth: .infinity).frame(height: 40)
            .background(fill, in: RoundedRectangle(cornerRadius: 11))
    }
}
