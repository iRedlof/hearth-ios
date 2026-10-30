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
    private var isSetup: Bool { snap.mode.isEmpty }                                       // no mode reported yet → setup
    private var isOff: Bool { snap.mode.caseInsensitiveCompare("Off") == .orderedSame }
    private var stale: Bool { snap.tone == .offline && !isSetup }                         // offline: dim the controls

    public var body: some View {
        GeometryReader { geo in
            let s = beaconSplit(width: geo.size.width)   // Android rail is ~37%, not 50%
            HStack(spacing: 0) {
                left.frame(width: s.rail)
                right.frame(maxWidth: .infinity)
            }
        }
    }

    // MARK: Left — readings
    private var left: some View {
        VStack(alignment: .leading, spacing: 0) {
            Image(systemName: "thermometer.medium").font(.system(size: 13)).foregroundStyle(ink.opacity(0.9))
            Text(snap.roomTemp).font(.system(size: 36, weight: .heavy)).tracking(-1).foregroundStyle(ink).padding(.top, 1)
            Text(snap.roomSub).font(.system(size: 12, weight: .medium)).foregroundStyle(ink)
            if let h = snap.humidity {
                Text(h).font(.system(size: 11)).foregroundStyle(ink.opacity(0.82)).lineLimit(1).minimumScaleFactor(0.8)
            }
            Text(snap.status).font(.system(size: 11)).foregroundStyle(ink.opacity(0.82)).lineLimit(1).minimumScaleFactor(0.75)
            Rectangle().fill(ink.opacity(0.26)).frame(height: 1).padding(.top, 4).padding(.bottom, 1)
            ForEach(snap.sensors.prefix(3), id: \.name) { s in
                HStack(spacing: 3) {
                    Text(s.name).font(.system(size: 11.5)).foregroundStyle(ink.opacity(0.82)).lineLimit(1)
                    Spacer(minLength: 2)
                    Text(s.value).font(.system(size: 12, weight: .bold)).foregroundStyle(ink).lineLimit(1)
                }.padding(.vertical, 0.5)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12).padding(.vertical, 11)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(LinearGradient(colors: [fill, fill.opacity(0.9)], startPoint: .topLeading, endPoint: .bottomTrailing))
    }

    // MARK: Right — controls
    private var right: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 6) {
                Text(snap.name).font(.system(size: 16, weight: .bold)).foregroundStyle(surfaceInk).lineLimit(1)
                Spacer(minLength: 2)
                // Use the shared freshness cluster (Checked stamp + circular refresh button to its RIGHT),
                // same as Alarm/Car/ChargePoint and Android — was a bespoke header (bare icon on the left).
                BeaconFreshness(checkedAt: snap.checkedAt, kind: "com.rohit.hearth.thermostat", ink: surfaceInk)
            }
            BeaconMiddle(maximumHeight: 92) { middleContent }
            if isSetup {
                connectButton
            } else {
                controlRow.opacity(stale ? 0.45 : 1).disabled(stale)
            }
        }
        .padding(.horizontal, 13).padding(.top, 11).padding(.bottom, 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(argb: BeaconSurfaceColors.graphiteARGB))
    }

    @ViewBuilder private var middleContent: some View {
        if isSetup {
            setupCta
        } else if isOff {
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
            }.opacity(stale ? 0.45 : 1).disabled(stale)
        }
    }

    /// The Mode / Fan / Resume chip row (shared by the normal and off layouts).
    private var controlRow: some View {
        HStack(spacing: 6) {
            Button(intent: ClimatePickerIntent("mode")) { chip("Mode", snap.mode) }.buttonStyle(.plain)
            if let fan = snap.fan {
                Button(intent: ClimatePickerIntent("fan")) { chip("Fan", fan) }.buttonStyle(.plain)
            }
            if snap.canResume {
                Button(intent: ClimateSetpointIntent("resume")) { chip(nil, "Resume") }.buttonStyle(.plain)
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
        Text("Connect").font(.system(size: 13, weight: .semibold)).foregroundStyle(surfaceInk)
            .frame(maxWidth: .infinity).frame(height: 34)
            .background(Color.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 9))
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
            Button(intent: ClimateSetpointIntent("\(side.rawValue)Down")) {
                Image(systemName: "minus.circle.fill").font(.system(size: 20)).foregroundStyle(surfaceInk.opacity(0.85))
            }.buttonStyle(.plain)
            Text(value).font(.system(size: 18, weight: .semibold)).foregroundStyle(Color(argb: valueColor))
                .lineLimit(1).frame(minWidth: 36)
            Button(intent: ClimateSetpointIntent("\(side.rawValue)Up")) {
                Image(systemName: "plus.circle.fill").font(.system(size: 20)).foregroundStyle(surfaceInk.opacity(0.85))
            }.buttonStyle(.plain)
        }
    }

    private func chip(_ label: String?, _ value: String) -> some View {
        VStack(spacing: 0) {
            if let label { Text(label).font(.system(size: 9)).foregroundStyle(surfaceInk.opacity(0.7)) }
            Text(value).font(.system(size: 12, weight: .semibold)).foregroundStyle(surfaceInk).lineLimit(1).minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity).frame(height: 34)
        .background(Color.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 9))
    }
}
