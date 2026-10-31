import SwiftUI
import AppIntents
import HearthKit

/// The Thermostat Beacon card, ported from the Android `ClimateWidget`: a tone-coloured left panel
/// (mode colour — yellow heat, blue cool, violet auto, slate off) with the room temperature, humidity,
/// honest status headline, and sensor rows; a dark right panel with the Heat-to / Cool-to setpoints and
/// a Mode / Fan / Resume row.
public struct ThermostatBeaconView: View {
    public let snap: ThermostatSnapshot
    public init(_ snap: ThermostatSnapshot) { self.snap = snap }

    private var fill: Color { Color(argb: snap.tone.fillARGB) }
    private var ink: Color { Color(argb: snap.tone.inkARGB) }
    private var surfaceInk: Color { Color(argb: BeaconSurfaceColors.inkARGB) }
    private var isSetup: Bool { snap.setup }
    private var isOff: Bool { snap.mode.caseInsensitiveCompare("Off") == .orderedSame }
    private var stale: Bool { snap.stale }

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

    // MARK: Left — readings
    private func left(compact: Bool) -> some View {
        // At 155pt with humidity and all three sensors: 43+15+15+15+3+3×16+14 = 153pt.
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(snap.roomTemp).font(.system(size: 36, weight: .heavy)).tracking(-1).foregroundStyle(ink)
                    .lineLimit(1)
                Spacer(minLength: 0)
                Image(systemName: "thermometer.medium").font(.system(size: 13)).foregroundStyle(ink.opacity(0.9))
            }
            .frame(height: 43, alignment: .leading)
            Text(snap.roomSub).font(.system(size: 12, weight: .medium)).foregroundStyle(ink)
                .lineLimit(1).frame(height: 15, alignment: .leading)
            if let h = snap.humidity {
                Text(h).font(.system(size: 12)).foregroundStyle(ink.opacity(0.82)).lineLimit(1)
                    .frame(height: 15, alignment: .leading)
            }
            Text(snap.commandFeedback ?? snap.status).font(.system(size: 12)).foregroundStyle(ink.opacity(0.82)).lineLimit(1)
                .frame(height: 15, alignment: .leading)
                .accessibilityLabel(snap.commandError ?? snap.error ?? snap.commandFeedback ?? snap.status)
            Rectangle().fill(ink.opacity(0.26)).frame(height: 1).padding(.vertical, compact ? 1 : 2)
            ForEach(snap.sensors.prefix(3), id: \.id) { s in
                HStack(spacing: 3) {
                    Text(s.name).font(.system(size: 12)).foregroundStyle(ink.opacity(0.82)).lineLimit(1)
                    Spacer(minLength: 2)
                    HStack(spacing: 2) {
                        if s.stale {
                            Image(systemName: "clock").font(.system(size: 10)).foregroundStyle(ink.opacity(0.85))
                        }
                        Text(s.value).font(.system(size: 12, weight: .bold)).foregroundStyle(ink).lineLimit(1)
                    }.layoutPriority(1)
                }.frame(height: compact ? 16 : 17)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(s.name), \(s.value)\(s.stale ? ", last known" : "")")
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12).padding(.vertical, compact ? 7 : 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(LinearGradient(colors: [fill, fill.opacity(0.9)], startPoint: .topLeading, endPoint: .bottomTrailing))
    }

    // MARK: Right — controls
    private func right(compact: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 6) {
                Text(snap.name).font(.system(size: 16, weight: .bold)).foregroundStyle(surfaceInk).lineLimit(1)
                Spacer(minLength: 2)
                // Use the shared freshness cluster (Checked stamp + circular refresh button to its RIGHT),
                // same as Alarm/Car/ChargePoint and Android — was a bespoke header (bare icon on the left).
                BeaconFreshness(checkedAt: snap.checkedAt, kind: "com.rohit.hearth.thermostat", ink: surfaceInk)
            }
            .frame(height: 26, alignment: .top)
            BeaconMiddle(maximumHeight: 92) { middleContent }
            if isSetup || snap.needsSettings {
                connectButton
            } else {
                controlRow
            }
        }
        .padding(.horizontal, 13).padding(.top, compact ? 8 : 11).padding(.bottom, 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(argb: BeaconSurfaceColors.graphiteARGB))
    }

    @ViewBuilder private var middleContent: some View {
        if isSetup {
            setupCta
        } else if isOff && !stale {
            offCard
        } else if snap.heatSetpoint == nil && snap.coolSetpoint == nil {
            VStack(spacing: 3) {
                Text(stale ? "Unavailable" : snap.mode).font(.system(size: 14, weight: .semibold))
                if !stale {
                    Text("No temperature target").font(.system(size: 12))
                        .foregroundStyle(surfaceInk.opacity(0.7)).multilineTextAlignment(.center)
                }
            }
            .foregroundStyle(surfaceInk).frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(alignment: .leading, spacing: 5) {
                if let heat = snap.heatSetpoint { setpointRow("Heat to", heat, 0xFFF6D58A, side: .heat) }
                if let cool = snap.coolSetpoint { setpointRow("Cool to", cool, 0xFFA6D5FF, side: .cool) }
            }.disabled(stale)
        }
    }

    /// The Mode / Fan / Resume chip row (shared by the normal and off layouts).
    private var controlRow: some View {
        HStack(spacing: 6) {
            if snap.canPickMode {
                Button(intent: ClimatePickerIntent("mode", entityID: snap.entityID, scope: snap.requestScope,
                    revision: snap.climateRevision)) {
                    chip("Mode", snap.mode, enabled: true)
                }.buttonStyle(.plain)
            } else {
                chip("Mode", snap.mode, enabled: snap.canPickMode)
            }
            if snap.hasFanControl {
                if snap.canPickFan {
                    Button(intent: ClimatePickerIntent("fan", entityID: snap.entityID, scope: snap.requestScope,
                        revision: snap.climateRevision)) {
                        chip("Fan", snap.fan ?? "—", enabled: true)
                    }.buttonStyle(.plain)
                } else {
                    chip("Fan", snap.fan ?? "—", enabled: false)
                }
            }
            if snap.hasResumeControl {
                if snap.canResume {
                    Button(intent: ClimateSetpointIntent("resume", entityID: snap.entityID,
                        scope: snap.requestScope, revision: snap.climateRevision, resumeID: snap.resumeID)) {
                        chip(nil, "Resume", enabled: true)
                    }.buttonStyle(.plain)
                } else {
                    chip(nil, "Resume", enabled: false)
                }
            }
        }
    }

    /// Setup middle CTA — a large recessed "Set up thermostat" button filling the mid-region (Android parity).
    private var setupCta: some View {
        Text("Set up thermostat").font(.system(size: 13, weight: .semibold)).foregroundStyle(surfaceInk)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 13))
    }

    /// Setup bottom action — a full-width "Connect" in place of the Mode/Fan/Resume row.
    private var connectButton: some View {
        Button(intent: HaSetupIntent(reconnect: snap.needsSignIn)) {
            Text(snap.needsSignIn ? "Sign in" : isSetup ? "Connect" : "Open Settings")
                .font(.system(size: 13, weight: .semibold)).foregroundStyle(surfaceInk)
                .frame(maxWidth: .infinity).frame(height: 34)
                .background(Color.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 9))
        }.buttonStyle(.plain)
    }

    /// Off middle message — a recessed card "Off / Choose a mode to turn on" (Android parity).
    private var offCard: some View {
        VStack(spacing: 3) {
            Text("Off").font(.system(size: 14, weight: .semibold)).foregroundStyle(surfaceInk)
            Text("Choose a mode to turn on").font(.system(size: 12)).foregroundStyle(surfaceInk.opacity(0.7))
                .multilineTextAlignment(.center).lineLimit(2).minimumScaleFactor(0.8)
        }
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 13))
    }

    private func setpointRow(_ label: String, _ value: String, _ valueColor: UInt32, side: ClimateSide) -> some View {
        HStack(spacing: 5) {
            Text(label).font(.system(size: 12)).foregroundStyle(surfaceInk).lineLimit(1).minimumScaleFactor(0.8)
            Spacer(minLength: 2)
            Button(intent: ClimateSetpointIntent("\(side.rawValue)Down", entityID: snap.entityID,
                scope: snap.requestScope, revision: snap.climateRevision)) {
                Image(systemName: "minus.circle.fill").font(.system(size: 20)).foregroundStyle(surfaceInk.opacity(0.85))
            }.buttonStyle(.plain).disabled(!canAdjust(side, up: false)).opacity(canAdjust(side, up: false) ? 1 : 0.4)
            Text(value).font(.system(size: 18, weight: .semibold))
                .foregroundStyle(stale ? Color(argb: BeaconTone.offline.fillARGB) : Color(argb: valueColor))
                .lineLimit(1).frame(minWidth: 36)
            Button(intent: ClimateSetpointIntent("\(side.rawValue)Up", entityID: snap.entityID,
                scope: snap.requestScope, revision: snap.climateRevision)) {
                Image(systemName: "plus.circle.fill").font(.system(size: 20)).foregroundStyle(surfaceInk.opacity(0.85))
            }.buttonStyle(.plain).disabled(!canAdjust(side, up: true)).opacity(canAdjust(side, up: true) ? 1 : 0.4)
        }
    }

    private func canAdjust(_ side: ClimateSide, up: Bool) -> Bool {
        side == .heat ? (up ? snap.canAdjustHeatUp : snap.canAdjustHeatDown)
            : (up ? snap.canAdjustCoolUp : snap.canAdjustCoolDown)
    }

    private func chip(_ label: String?, _ value: String, enabled: Bool) -> some View {
        VStack(spacing: 0) {
            if let label { Text(label).font(.system(size: 9)).foregroundStyle(surfaceInk.opacity(0.7)) }
            Text(value).font(.system(size: 12, weight: .semibold))
                .foregroundStyle(surfaceInk.opacity(enabled ? 1 : 0.82))
                .lineLimit(1).minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity).frame(height: 34)
        .background(Color.white.opacity(enabled ? 0.1 : 0.06), in: RoundedRectangle(cornerRadius: 9))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label.map { $0 + ", " } ?? "")\(value)\(enabled ? "" : ", control unavailable")")
    }
}
