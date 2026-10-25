import SwiftUI
import AppIntents
import HearthKit

/// The Alarm Beacon card, ported from the Android `AlarmWidget` (v1.4.26): a tone-coloured left rail
/// (the security state's colour) with the shield glyph + state word + the always-shown "<state> at <time>"
/// line; a dark right surface with the home name, the Front Door lock row, and the arm/disarm buttons.
public struct AlarmBeaconView: View {
    public let snap: AlarmSnapshot
    public init(_ snap: AlarmSnapshot) { self.snap = snap }

    private var fill: Color { Color(argb: snap.tone.fillARGB) }
    private var ink: Color { Color(argb: snap.tone.inkARGB) }                 // dark text on the light tone rail
    private var surfaceInk: Color { Color(argb: BeaconSurfaceColors.inkARGB) } // bright text on graphite
    private var doorStatusColor: Color {
        switch snap.doorLocked {
        case .some(true):  return Color(argb: 0xFF8FD6A8)   // green when locked
        case .some(false): return Color(argb: 0xFFF2A0A4)   // red when unlocked
        case nil:          return surfaceInk.opacity(0.75)  // unknown / in-transit
        }
    }

    public var body: some View {
        GeometryReader { geo in
            let s = beaconSplit(width: geo.size.width)   // Android rail is ~37%, not 50%
            HStack(spacing: 0) {
                rail.frame(width: s.rail)
                surface.frame(maxWidth: .infinity)
            }
        }
    }

    // MARK: Left — tone rail (the security state)
    private var rail: some View {
        VStack(alignment: .leading, spacing: 0) {
            Image(systemName: glyphSymbol).font(.system(size: 34, weight: .semibold)).foregroundStyle(ink)
            Spacer(minLength: 4)
            Text(snap.stateWord)
                .font(.system(size: snap.stateWord.count > 10 ? 20 : 25, weight: .heavy)).tracking(-0.5)
                .foregroundStyle(ink).lineLimit(2).minimumScaleFactor(0.7).fixedSize(horizontal: false, vertical: true)
            Text(snap.detail).font(.system(size: 11)).foregroundStyle(ink.opacity(0.82))
                .lineLimit(1).minimumScaleFactor(0.7).padding(.top, 3)
        }
        .padding(.horizontal, 13).padding(.vertical, 13)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(LinearGradient(colors: [fill, fill.opacity(0.88)], startPoint: .topLeading, endPoint: .bottomTrailing))
    }

    // MARK: Right — dark surface (home, door, actions)
    private var surface: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 6) {
                Text(alarmTitle).font(.system(size: 14, weight: .semibold)).foregroundStyle(surfaceInk).lineLimit(1)
                Spacer(minLength: 2)
                BeaconFreshness(checkedAt: snap.checkedAt, kind: "com.rohit.hearth.alarm", ink: surfaceInk)
            }
            if snap.stateWord == "Set up" {   // match Android's setup card: a message + a Connect button
                Spacer(minLength: 6)
                Text("Connect your alarm").font(.system(size: 13)).foregroundStyle(surfaceInk.opacity(0.85))
                Spacer(minLength: 8)
                Text("Connect").font(.system(size: 13, weight: .semibold)).foregroundStyle(Color(white: 0.12))
                    .frame(maxWidth: .infinity).frame(height: 34)
                    .background(Color(white: 0.94), in: RoundedRectangle(cornerRadius: 10))
            } else {
                Spacer(minLength: 6)
                doorRow
                Spacer(minLength: 6)
                actionsRow
            }
        }
        .padding(.horizontal, 13).padding(.vertical, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(argb: BeaconSurfaceColors.graphiteARGB))
    }

    /// The Front Door well: lock status (left) + an explicit Unlock / Lock button (right, with icon),
    /// matching Android's door well. Unlock is Face-ID-gated in place; Lock runs in place.
    private var doorRow: some View {
        HStack(spacing: 8) {
            Image(systemName: (snap.doorLocked ?? true) ? "lock.fill" : "lock.open.fill")
                .font(.system(size: 17)).foregroundStyle(surfaceInk.opacity(0.9)).frame(width: 20)
            VStack(alignment: .leading, spacing: 1) {
                Text(snap.doorName).font(.system(size: 12.5, weight: .medium)).foregroundStyle(surfaceInk).lineLimit(1).minimumScaleFactor(0.7)
                // Status green when locked, red when unlocked; "since …" on its own line so neither clips.
                Text(snap.doorState).font(.system(size: 10.5, weight: .semibold)).foregroundStyle(doorStatusColor).lineLimit(1).minimumScaleFactor(0.8)
                if let since = snap.doorSince {
                    Text(since).font(.system(size: 10.5)).foregroundStyle(surfaceInk.opacity(0.6)).lineLimit(1).minimumScaleFactor(0.8)
                }
            }
            Spacer(minLength: 4)
            if let locked = snap.doorLocked { doorButton(locked) }
        }
        .padding(9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 11))
    }

    @ViewBuilder private func doorButton(_ locked: Bool) -> some View {
        // Text-only, matching Android — the door row's lock glyph already shows the state, so the button
        // needn't repeat it.
        let label = Text(locked ? "Unlock" : "Lock").font(.system(size: 12, weight: .semibold)).lineLimit(1)
            .foregroundStyle(surfaceInk).padding(.horizontal, 14).frame(height: 30)
            .background(Color.white.opacity(0.14), in: RoundedRectangle(cornerRadius: 9))
            .fixedSize(horizontal: true, vertical: false)
        if locked {
            Button(intent: AlarmGatedIntent(.unlock)) { label }.buttonStyle(.plain)
        } else {
            Button(intent: AlarmControlIntent(LockAction.lock.rawValue)) { label }.buttonStyle(.plain)
        }
    }

    private var actionsRow: some View {
        HStack(spacing: 7) {
            ForEach(snap.actions, id: \.self) { action in
                if action.needsConfirm {   // Disarm → Face ID gate (opens app)
                    Button(intent: AlarmGatedIntent(.disarm)) { actionLabel(action) }
                        .buttonStyle(.plain)
                } else {                    // Arm home / Arm away → in place
                    Button(intent: AlarmControlIntent(action.rawValue)) { actionLabel(action) }
                        .buttonStyle(.plain)
                }
            }
        }
    }

    /// A pill styled like the Android action button (now with an icon); Disarm is the bright "primary" pill.
    private func actionLabel(_ action: AlarmAction) -> some View {
        let primary = (action == .disarm)
        return HStack(spacing: 5) {
            Image(systemName: armIcon(action)).font(.system(size: 11, weight: .semibold))
            Text(action.label).font(.system(size: 12, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.8)
        }
        .foregroundStyle(primary ? Color(white: 0.12) : surfaceInk)
        .frame(maxWidth: .infinity).frame(height: 34)
        .background(primary ? Color(white: 0.94) : Color.white.opacity(0.12),
                    in: RoundedRectangle(cornerRadius: 10))
    }

    private func armIcon(_ action: AlarmAction) -> String {
        switch action {
        case .armHome: "house.fill"
        case .armAway: "shield.fill"
        case .disarm:  "shield.slash.fill"
        }
    }

    /// The home name without a trailing " Alarm" (Rohit prefers "Home", not "Home Alarm").
    private var alarmTitle: String {
        snap.name.hasSuffix(" Alarm") ? String(snap.name.dropLast(6)) : snap.name
    }

    private var glyphSymbol: String {
        switch snap.glyph {
        case .off:   "shield.slash.fill"
        case .home:  "house.fill"
        case .lock:  "lock.shield.fill"
        case .alert: "exclamationmark.shield.fill"
        }
    }
}
