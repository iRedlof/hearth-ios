#if DEBUG
import SwiftUI
import WidgetKit
import HearthKit

/// A native design spike. Fixtures have no provider reads, mutation intents or live command targets.
/// Small is recomposed around a single answer; it does not scale down a Medium/Large view.
struct SmallWidgetConcept {
    let kind: String
    let state: String
    let title: String
    let symbol: String
    let answer: String
    let context: String
    let actions: [String]
    var tone: BeaconTone = .mint
    var darkSurface = false
    var answerSize: CGFloat = 36
    var auto: Bool?
    var carImage = false
    var site: String?
    var actionPending = false

    var id: String { "small-\(kind)-\(state)" }
}

@MainActor
enum SmallWidgetConceptCatalog {
    static let concepts: [SmallWidgetConcept] = [
        .init(kind: "chargepoint", state: "available", title: "Day 1", symbol: "bolt.circle",
              answer: "78", context: "plugs free", actions: ["Join"], tone: .orange,
              auto: false, site: "Amazon Day 1"),
        .init(kind: "chargepoint", state: "waiting", title: "Day 1", symbol: "bolt.circle",
              answer: "#3", context: "In line", actions: ["Waitlist"], tone: .orange,
              auto: true, site: "Amazon Day 1"),
        .init(kind: "chargepoint", state: "offer", title: "Day 1", symbol: "bolt.circle",
              answer: "13:53", context: "Your turn · P3", actions: ["Accept"], tone: .orange,
              answerSize: 32, auto: true, site: "Amazon Day 1"),
        .init(kind: "chargepoint", state: "held", title: "Day 1", symbol: "bolt.circle",
              answer: "P3", context: "Plug in · 28:10", actions: ["Open app"], tone: .orange,
              auto: true, site: "Amazon Day 1"),
        .init(kind: "chargepoint", state: "snoozed", title: "Day 1", symbol: "bolt.circle",
              answer: "Snoozed", context: "Place kept · 8:42", actions: ["Rejoin"], tone: .orange,
              answerSize: 23, auto: true, site: "Amazon Day 1"),
        .init(kind: "chargepoint", state: "charging", title: "Day 1", symbol: "bolt.circle",
              answer: "7.4", context: "kWh · Charging", actions: ["Session"], tone: .orange,
              auto: true, site: "Amazon Day 1"),
        .init(kind: "chargepoint", state: "done", title: "Day 1", symbol: "bolt.circle",
              answer: "Move car", context: "Charging complete", actions: ["Open app"], tone: .orange,
              answerSize: 23, auto: false, site: "Amazon Day 1"),
        .init(kind: "chargepoint", state: "expired", title: "Day 1", symbol: "bolt.circle",
              answer: "Expired", context: "Offer ended", actions: ["Waitlist"], tone: .orange,
              answerSize: 24, auto: true, site: "Amazon Day 1"),
        .init(kind: "chargepoint", state: "unknown_deadline", title: "Day 1", symbol: "bolt.circle",
              answer: "Your turn", context: "Deadline unknown", actions: ["View offer"], tone: .orange,
              answerSize: 23, auto: true, site: "Amazon Day 1"),
        .init(kind: "chargepoint", state: "working", title: "Day 1", symbol: "bolt.circle",
              answer: "Your turn", context: "Accepting…", actions: ["Accepting…"], tone: .orange,
              answerSize: 23, auto: true, site: "Amazon Day 1", actionPending: true),
        .init(kind: "chargepoint", state: "signed_out", title: "ChargePoint", symbol: "bolt.circle",
              answer: "Sign in", context: "Connect account", actions: ["Sign in"], tone: .orange,
              answerSize: 26),
        .init(kind: "chargepoint", state: "no_location", title: "ChargePoint", symbol: "bolt.circle",
              answer: "Choose\nlocation", context: "", actions: ["Choose"], tone: .orange, answerSize: 22),
        .init(kind: "chargepoint", state: "stale", title: "Day 1", symbol: "bolt.circle",
              answer: "#3", context: "Last known", actions: ["Refresh"], tone: .orange,
              auto: true, site: "Amazon Day 1"),
        .init(kind: "alarm", state: "disarmed", title: "Home", symbol: "shield",
              answer: "Disarmed", context: "Front Door locked", actions: ["Arm\nhome", "Arm\naway"],
              tone: .blue, answerSize: 24),
        .init(kind: "alarm", state: "armed_home", title: "Home", symbol: "house.fill",
              answer: "Armed home", context: "Front Door locked", actions: ["Disarm"],
              tone: .red, answerSize: 21),
        .init(kind: "alarm", state: "armed_away", title: "Home", symbol: "car.fill",
              answer: "Armed away", context: "Front Door locked", actions: ["Disarm"],
              tone: .red, answerSize: 21),
        .init(kind: "alarm", state: "triggered", title: "Home", symbol: "exclamationmark.shield",
              answer: "Triggered", context: "Check your home", actions: ["View alarm"],
              tone: .triggered, answerSize: 24),
        .init(kind: "thermostat", state: "auto", title: "Thermostat", symbol: "thermometer.medium",
              answer: "71°", context: "Auto · 64–70°", actions: ["Adjust"], tone: .violet, answerSize: 40),
        .init(kind: "thermostat", state: "heat", title: "Thermostat", symbol: "thermometer.medium",
              answer: "68°", context: "Heating to 72°", actions: ["Adjust"], tone: .yellow, answerSize: 40),
        .init(kind: "thermostat", state: "cool", title: "Thermostat", symbol: "thermometer.medium",
              answer: "74°", context: "Cooling to 70°", actions: ["Adjust"], tone: .blue, answerSize: 40),
        .init(kind: "thermostat", state: "off", title: "Thermostat", symbol: "thermometer.medium",
              answer: "71°", context: "System off", actions: ["Choose mode"], tone: .slate, answerSize: 40),
        .init(kind: "thermostat", state: "stale", title: "Thermostat", symbol: "thermometer.medium",
              answer: "71°", context: "Last known · Auto", actions: ["Refresh"], tone: .offline, answerSize: 40),
        .init(kind: "car", state: "parked", title: "Stargate", symbol: "car",
              answer: "72%", context: "219 mi range", actions: ["Open Tesla"], tone: .mint,
              answerSize: 30, carImage: true),
        .init(kind: "car", state: "charging", title: "Stargate", symbol: "car",
              answer: "72%", context: "Charging · 7 kW", actions: ["Open Tesla"], tone: .mint,
              answerSize: 30, carImage: true),
        .init(kind: "car", state: "open", title: "Stargate", symbol: "car",
              answer: "72%", context: "2 doors open", actions: ["Open Tesla"], tone: .yellow,
              answerSize: 30, carImage: true),
        .init(kind: "car", state: "low", title: "Stargate", symbol: "car",
              answer: "12%", context: "Low battery", actions: ["Open Tesla"], tone: .red,
              answerSize: 30, carImage: true),
        .init(kind: "lights", state: "on", title: "Lights", symbol: "lightbulb",
              answer: "Desk Lamp", context: "On · 80%", actions: ["Turn off"],
              darkSurface: true, answerSize: 23),
        .init(kind: "lights", state: "off", title: "Lights", symbol: "lightbulb",
              answer: "Desk Lamp", context: "Off", actions: ["Turn on"],
              darkSurface: true, answerSize: 23),
        .init(kind: "lights", state: "long_name", title: "Lights", symbol: "lightbulb",
              answer: "Bedroom\nreading lamp", context: "On · 80%", actions: ["Turn off"],
              darkSurface: true, answerSize: 20),
        .init(kind: "quick", state: "ready", title: "Quick", symbol: "bolt",
              answer: "Good Night", context: "Ready", actions: ["Run"], darkSurface: true,
              answerSize: 23),
        .init(kind: "quick", state: "working", title: "Quick", symbol: "bolt",
              answer: "Good Night", context: "Waiting for result", actions: ["Running…"],
              darkSurface: true, answerSize: 24, actionPending: true),
        .init(kind: "quick", state: "long_name", title: "Quick", symbol: "bolt",
              answer: "Downstairs\nmovie time", context: "Ready", actions: ["Run"],
              darkSurface: true, answerSize: 20),
        .init(kind: "favourites", state: "on", title: "Favourites", symbol: "star",
              answer: "Coffee Maker", context: "On", actions: ["Turn off"],
              darkSurface: true, answerSize: 20),
        .init(kind: "favourites", state: "off", title: "Favourites", symbol: "star",
              answer: "Coffee Maker", context: "Off", actions: ["Turn on"],
              darkSurface: true, answerSize: 20),
        .init(kind: "favourites", state: "long_name", title: "Favourites", symbol: "star",
              answer: "Theater\nfloor lamp", context: "On", actions: ["Turn off"],
              darkSurface: true, answerSize: 20),
        .init(kind: "doors", state: "locked", title: "Front Door", symbol: "door.left.hand.closed",
              answer: "Locked", context: "Since 9:18 PM", actions: ["Unlock"], darkSurface: true,
              answerSize: 28),
        .init(kind: "doors", state: "unlocked", title: "Front Door", symbol: "door.left.hand.open",
              answer: "Unlocked", context: "Check your door", actions: ["Lock"], tone: .yellow,
              darkSurface: true, answerSize: 24),
        .init(kind: "doors", state: "moving", title: "Garage", symbol: "door.garage.open",
              answer: "Opening", context: "In motion", actions: ["Stop"], tone: .yellow,
              darkSurface: true, answerSize: 26),
        .init(kind: "doors", state: "long_name", title: "Doors", symbol: "door.left.hand.open",
              answer: "Back patio\ndoor", context: "Unlocked", actions: ["Lock"], tone: .yellow,
              darkSurface: true, answerSize: 20),
        .init(kind: "battery", state: "low", title: "Batteries", symbol: "battery.25",
              answer: "9%", context: "Front Door · 2 low", actions: ["View batteries"],
              tone: .red, darkSurface: true, answerSize: 40),
        .init(kind: "battery", state: "binary_low", title: "Batteries", symbol: "battery.25",
              answer: "Low", context: "Leak Sensor · 1 low", actions: ["View batteries"],
              tone: .yellow, darkSurface: true),
        .init(kind: "battery", state: "unknown", title: "Batteries", symbol: "battery.0",
              answer: "Unknown", context: "2 unavailable", actions: ["View batteries"],
              tone: .offline, darkSurface: true, answerSize: 24),
        .init(kind: "activity", state: "recent", title: "Activity", symbol: "clock",
              answer: "Front Door", context: "Unlocked · 9:18 PM", actions: ["View activity"],
              darkSurface: true, answerSize: 22),
        .init(kind: "activity", state: "empty", title: "Activity", symbol: "clock",
              answer: "No recent\nactivity", context: "", actions: ["View activity"],
              darkSurface: true, answerSize: 22)
    ] + recoveryConcepts()

    private static func recoveryConcepts() -> [SmallWidgetConcept] {
        let kinds = ["chargepoint", "alarm", "thermostat", "car", "lights", "quick",
                     "favourites", "doors", "battery", "activity"]
        let names = ["Day 1", "Home", "Thermostat", "Stargate", "Desk Lamp", "Good Night",
                     "Coffee Maker", "Front Door", "Batteries", "Activity"]
        let symbols = ["bolt.circle", "shield", "thermometer.medium", "car", "lightbulb", "bolt",
                       "star", "door.left.hand.closed", "battery.0", "clock"]
        return kinds.indices.flatMap { i -> [SmallWidgetConcept] in
            let dark = i >= 4
            return [
                .init(kind: kinds[i], state: "unavailable", title: names[i], symbol: symbols[i],
                      answer: "Unavailable", context: "No current reading", actions: ["Refresh"],
                      tone: .offline, darkSurface: dark, answerSize: 20,
                      site: i == 0 ? "Amazon Day 1" : nil),
                .init(kind: kinds[i], state: "setup",
                      title: i == 0 ? "ChargePoint" : WidgetPreviewKind(rawValue: kinds[i])!.title,
                      symbol: symbols[i],
                      answer: ["Sign in", "Set up", "Set up", "Set up", "Choose\na light",
                               "Choose\na routine", "Choose a\nfavourite", "Choose\na door",
                               "Set up", "Set up"][i],
                      context: [ "Connect account", "Connect your home", "Choose thermostat",
                                 "Choose your car", "", "", "", "", "Select batteries", "Connect your home"][i],
                      actions: [[ "Sign in"], ["Connect"], ["Choose"], ["Choose"], ["Choose"],
                                ["Choose"], ["Choose"], ["Choose"], ["Choose"], ["Connect"]][i],
                      tone: .offline, darkSurface: dark, answerSize: 22)
            ]
        }
    }

    static func view(_ id: String) -> AnyView? {
        concepts.first { $0.id == id }.map { AnyView(SmallWidgetConceptView(concept: $0)) }
    }
}

struct SmallWidgetConceptView: View {
    let concept: SmallWidgetConcept
    private var ink: Color {
        Color(argb: concept.darkSurface ? BeaconSurfaceColors.inkARGB : concept.tone.inkARGB)
    }
    private var accent: Color { Color(argb: concept.tone.fillARGB) }

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            header.frame(height: 20)
            answer.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            actionRow.frame(height: 44)
        }
        .padding(11)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            if concept.darkSurface {
                LinearGradient(colors: [Color(argb: 0xFF353D37), Color(argb: 0xFF202722)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
            } else {
                LinearGradient(colors: [accent, accent.opacity(0.86)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
            }
        }
        .overlay(ContainerRelativeShape().strokeBorder(.white.opacity(0.24), lineWidth: 1))
        .allowsHitTesting(false)
        .accessibilityIdentifier(concept.id)
    }

    private var header: some View {
        HStack(spacing: 5) {
            if concept.kind == "chargepoint" {
                Image("CpLogo").renderingMode(.template).resizable().scaledToFit()
                    .frame(width: 18, height: 18)
            } else {
                Image(systemName: concept.symbol)
                    .resizable().scaledToFit()
                    .font(.system(size: 17, weight: .medium))
                    .frame(width: 18, height: 18)
            }
            Text(concept.title).font(.system(size: 14, weight: .semibold)).lineLimit(1)
                .accessibilityLabel(concept.site ?? concept.title)
            if let auto = concept.auto {
                Spacer(minLength: 0)
                HStack(spacing: 4) {
                    Text("Auto").font(.system(size: 13, weight: .semibold))
                    Circle().fill(Color(argb: auto ? 0xFF208345 : 0xFF626A63))
                        .frame(width: 7, height: 7)
                }
                .padding(.horizontal, 6).frame(height: 20)
                .background(ink.opacity(0.08), in: Capsule())
                .overlay(Capsule().strokeBorder(ink.opacity(0.2), lineWidth: 0.75))
                .fixedSize(horizontal: true, vertical: false)
                .accessibilityLabel(auto ? "Auto on" : "Auto off")
            }
        }
        .foregroundStyle(ink)
    }

    private var answer: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 4) {
                Text(concept.answer)
                    .font(.system(size: concept.answerSize, weight: .heavy))
                    .monospacedDigit().tracking(-0.7)
                    .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                    .layoutPriority(1)
                if concept.carImage {
                    Image("CarPremium").resizable().scaledToFit().frame(width: 52, height: 30)
                        .accessibilityHidden(true)
                }
            }
            if !concept.context.isEmpty {
                Text(concept.context).font(.system(size: 14, weight: .medium))
                    .lineLimit(1).fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .foregroundStyle(concept.darkSurface ? accent : ink)
    }

    private var actionRow: some View {
        HStack(spacing: 8) {
            ForEach(concept.actions, id: \.self) { label in
                Text(label)
                    .font(.system(size: concept.actions.count == 1 ? 16 : 14, weight: .semibold))
                    .multilineTextAlignment(.center).lineLimit(2)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .foregroundStyle(Color(argb: BeaconSurfaceColors.inkARGB))
                    .background {
                        RoundedRectangle(cornerRadius: 11, style: .continuous)
                            .fill(LinearGradient(colors: [Color(argb: 0xFF465249), Color(argb: 0xFF252E28)],
                                                 startPoint: .top, endPoint: .bottom))
                    }
                    .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .strokeBorder(.white.opacity(0.16), lineWidth: 0.75))
                    .opacity(concept.actionPending ? 0.75 : 1)
                    .accessibilityLabel(label.replacingOccurrences(of: "\n", with: " ") + ". Design mock")
            }
        }
    }
}
#endif
