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

    public var body: some View {
        HStack(spacing: 0) {
            rail.frame(maxWidth: .infinity)
            surface.frame(maxWidth: .infinity)
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
                Text(snap.name).font(.system(size: 14, weight: .semibold)).foregroundStyle(surfaceInk).lineLimit(1)
                Spacer(minLength: 2)
                VStack(alignment: .trailing, spacing: -1) {
                    Text("Checked").font(.system(size: 10))
                    Text(snap.checkedAt).font(.system(size: 10))
                }.foregroundStyle(surfaceInk.opacity(0.78))
            }
            Spacer(minLength: 6)
            doorRow
            Spacer(minLength: 6)
            actionsRow
        }
        .padding(.horizontal, 13).padding(.vertical, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(argb: BeaconSurfaceColors.graphiteARGB))
    }

    /// The door row doubles as the Lock/Unlock button when a lock is configured (tap toggles it).
    @ViewBuilder private var doorRow: some View {
        if let locked = snap.doorLocked {
            if locked {   // Unlock → Face ID gate (opens app)
                Button(intent: AlarmGatedIntent(.unlock)) { doorRowContent }.buttonStyle(.plain)
            } else {       // Lock → in place
                Button(intent: AlarmControlIntent(LockAction.lock.rawValue)) { doorRowContent }.buttonStyle(.plain)
            }
        } else {
            doorRowContent
        }
    }

    private var doorRowContent: some View {
        HStack(spacing: 8) {
            Image(systemName: (snap.doorLocked ?? true) ? "lock.fill" : "lock.open.fill")
                .font(.system(size: 17)).foregroundStyle(surfaceInk.opacity(0.9)).frame(width: 20)
            VStack(alignment: .leading, spacing: 1) {
                Text(snap.doorName).font(.system(size: 12.5, weight: .medium)).foregroundStyle(surfaceInk).lineLimit(1)
                Text([snap.doorState, snap.doorSince].compactMap { $0 }.joined(separator: " · "))
                    .font(.system(size: 10.5)).foregroundStyle(surfaceInk.opacity(0.75)).lineLimit(1).minimumScaleFactor(0.8)
            }
            Spacer(minLength: 0)
        }
        .padding(9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 11))
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

    /// A pill styled like the Android action button; Disarm is the bright "primary" pill.
    private func actionLabel(_ action: AlarmAction) -> some View {
        let primary = (action == .disarm)
        return Text(action.label)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(primary ? Color(white: 0.12) : surfaceInk)
            .frame(maxWidth: .infinity).frame(height: 34)
            .background(primary ? Color(white: 0.94) : Color.white.opacity(0.12),
                        in: RoundedRectangle(cornerRadius: 10))
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
