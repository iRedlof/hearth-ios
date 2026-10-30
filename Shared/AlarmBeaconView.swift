import SwiftUI
import AppIntents
import HearthKit

/// Actual panel/door telemetry with a centered door well and controls bound to their rendered origin.
public struct AlarmBeaconView: View {
    public let snap: AlarmSnapshot
    public init(_ snap: AlarmSnapshot) { self.snap = snap }

    private var fill: Color { Color(argb: snap.tone.fillARGB) }
    private var ink: Color { Color(argb: snap.tone.inkARGB) }                 // dark text on the light tone rail
    private var surfaceInk: Color { Color(argb: BeaconSurfaceColors.inkARGB) } // bright text on graphite
    private var hasOrigin: Bool { !snap.requestScope.isEmpty && !snap.alarmRevision.isEmpty }
    private var doorStatusColor: Color {
        if snap.doorStale || snap.doorError != nil { return surfaceInk.opacity(0.78) }
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
            Text(snap.commandFeedback ?? snap.detail).font(.system(size: 12)).foregroundStyle(ink.opacity(0.82))
                .lineLimit(3).padding(.top, 3)
                .accessibilityLabel(snap.commandError ?? snap.commandFeedback ?? snap.detail)
        }
        .padding(.horizontal, 13).padding(.vertical, 13)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(LinearGradient(colors: [fill, fill.opacity(0.88)], startPoint: .topLeading, endPoint: .bottomTrailing))
    }

    // MARK: Right — dark surface (home, door, actions)
    private var surface: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 6) {
                Text(alarmTitle).font(.system(size: 16, weight: .bold)).foregroundStyle(surfaceInk).lineLimit(1)
                Spacer(minLength: 2)
                BeaconFreshness(checkedAt: snap.checkedAt, kind: "com.rohit.hearth.alarm", ink: surfaceInk)
            }
            BeaconMiddle(maximumHeight: 72) {
                if snap.setup {
                    Text("Set up home alarm").font(.system(size: 14, weight: .semibold)).foregroundStyle(surfaceInk)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 13))
                } else {
                    doorRow
                }
            }
            if snap.setup || snap.error.map(beaconNeedsSettings) == true || snap.error.map(beaconNeedsSignIn) == true {
                Button(intent: HaSetupIntent(reconnect: snap.needsSignIn)) {
                    Text(snap.needsSignIn ? "Sign in" : snap.setup ? "Connect" : "Open Settings")
                        .font(.system(size: 14, weight: .semibold)).foregroundStyle(surfaceInk)
                        .frame(maxWidth: .infinity).frame(height: 34)
                        .background(Color.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
                }.buttonStyle(.plain)
            } else {
                actionsRow
            }
        }
        .padding(.horizontal, 13).padding(.top, 11).padding(.bottom, 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(argb: BeaconSurfaceColors.graphiteARGB))
    }

    /// Independent lock freshness; unknown and historical readings never imply a freshly secure door.
    @ViewBuilder private var doorRow: some View {
        if snap.doorSelected {
            selectedDoorRow
        } else {
            Button(intent: HaSetupIntent(reconnect: false)) {
                VStack(spacing: 4) {
                    Label("No door selected", systemImage: "questionmark.circle")
                        .font(.system(size: 13, weight: .semibold)).foregroundStyle(surfaceInk)
                    Text("Choose a door in Settings").font(.system(size: 12))
                        .foregroundStyle(surfaceInk.opacity(0.8))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 11))
            }.buttonStyle(.plain)
        }
    }

    private var selectedDoorRow: some View {
        HStack(spacing: 8) {
            Image(systemName: snap.doorStale ? "clock" : snap.doorLocked.map { $0 ? "lock.fill" : "lock.open.fill" } ?? "questionmark.circle")
                .font(.system(size: 17)).foregroundStyle(surfaceInk.opacity(0.9)).frame(width: 20)
            VStack(alignment: .leading, spacing: 1) {
                Text(snap.doorName).font(.system(size: 13, weight: .semibold)).foregroundStyle(surfaceInk).lineLimit(1)
                // Status green when locked, red when unlocked; "since …" on its own line so neither clips.
                Text(snap.doorState).font(.system(size: 12, weight: .semibold)).foregroundStyle(doorStatusColor).lineLimit(1)
                if let since = snap.doorSince {
                    Text(snap.doorStale ? since.replacingOccurrences(of: "Last checked ", with: "") : since)
                        .font(.system(size: 11.5)).foregroundStyle(surfaceInk.opacity(0.75)).lineLimit(1)
                        .accessibilityLabel(since)
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
            if let action = snap.doorAction {
                doorButton(action)
            } else if !snap.doorSelected || snap.doorError.map(beaconNeedsSettings) == true
                        || snap.doorError.map(beaconNeedsSignIn) == true {
                Button(intent: HaSetupIntent(reconnect: snap.doorError.map(beaconNeedsSignIn) == true)) {
                    doorLabel(snap.doorError.map(beaconNeedsSignIn) == true ? "Sign in" : "Settings")
                }.buttonStyle(.plain)
            } else if snap.commandPending && snap.doorLocked != nil {
                doorLabel(snap.doorLocked == true ? "Unlock" : "Lock").opacity(0.7)
            }
        }
        .padding(9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 11))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(snap.doorName), \(snap.doorStale ? "last known " : "")\(snap.doorState). \(snap.doorError ?? "")")
    }

    private func doorLabel(_ text: String) -> some View {
        Text(text).font(.system(size: 13, weight: .semibold)).lineLimit(1)
            .foregroundStyle(surfaceInk).padding(.horizontal, 8).frame(height: 32)
            .background(Color.white.opacity(0.14), in: RoundedRectangle(cornerRadius: 9))
            .fixedSize(horizontal: true, vertical: false)
    }
    @ViewBuilder private func doorButton(_ action: LockAction) -> some View {
        if !hasOrigin {
            doorLabel(action.label)
        } else if action == .unlock {
            Button(intent: AlarmGatedIntent(action.rawValue, snapshot: snap, entityID: snap.lockID)) {
                doorLabel(action.label)
            }.buttonStyle(.plain)
        } else {
            Button(intent: AlarmControlIntent(action.rawValue, snapshot: snap, entityID: snap.lockID)) {
                doorLabel(action.label)
            }.buttonStyle(.plain)
        }
    }

    private var actionsRow: some View {
        HStack(spacing: 7) {
            if snap.actionSlots.isEmpty {
                Text(snap.commandPending ? "Updating…" : snap.stale || snap.error != nil ? "Refresh to check" : "No supported controls")
                    .font(.system(size: 12)).foregroundStyle(surfaceInk.opacity(0.75))
                    .frame(maxWidth: .infinity).frame(height: 34)
            }
            ForEach(snap.actionSlots, id: \.self) { action in
                if !hasOrigin || !snap.actions.contains(action) {
                    actionLabel(action).opacity(snap.commandPending ? 0.7 : 1)
                } else if action.needsConfirm {
                    Button(intent: AlarmGatedIntent(action.rawValue, snapshot: snap, entityID: snap.entityID)) { actionLabel(action) }
                        .buttonStyle(.plain)
                } else {                    // Arm home / Arm away → in place
                    Button(intent: AlarmControlIntent(action.rawValue, snapshot: snap, entityID: snap.entityID)) { actionLabel(action) }
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
            Text(action.label).font(.system(size: 13, weight: .semibold)).lineLimit(1)
        }
        .foregroundStyle(primary ? Color(white: 0.12) : surfaceInk)
        .frame(maxWidth: .infinity).frame(height: 34)
        .background(primary ? Color(white: 0.94) : Color.white.opacity(0.12),
                    in: RoundedRectangle(cornerRadius: 10))
    }

    private func armIcon(_ action: AlarmAction) -> String {
        switch action {
        case .armHome: "house.fill"
        case .armAway: "car.fill"
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
