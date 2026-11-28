import SwiftUI
import AppIntents
import HearthKit
import WidgetKit

/// The Thermostat Beacon card, ported from the Android `ClimateWidget`: a tone-coloured left panel
/// (mode colour — yellow heat, blue cool, violet auto, slate off) with the room temperature, humidity,
/// honest status headline, and sensor rows; a dark right panel with the Heat-to / Cool-to setpoints and
/// a Mode / Fan / Resume row.
public struct ThermostatBeaconView: View {
    public let snap: ThermostatSnapshot
    private let payload: ThermostatEntryPayload?
    private let family: WidgetFamily
    /// The opened Mode/Fan choices for this exact entry; nil draws the ordinary Mode / Fan / Resume row.
    private let inlineChoices: ThermostatInlineChoices?
    /// Only the Home Screen widget opens choices in its own row; in-app hosts keep the in-app picker.
    private let inlinePicker: Bool
    @Environment(\.dynamicTypeSize) private var dynamicType
    @Environment(\.cardStyle) private var cardStyle

    public init(_ snap: ThermostatSnapshot, family: WidgetFamily = .systemMedium,
                inlineChoices: ThermostatInlineChoices? = nil, inlinePicker: Bool = false) {
        self.snap = snap
        self.payload = nil
        self.family = family
        self.inlineChoices = inlineChoices
        self.inlinePicker = inlinePicker
    }
    public init(_ payload: ThermostatEntryPayload, family: WidgetFamily = .systemMedium,
                inlineChoices: ThermostatInlineChoices? = nil, inlinePicker: Bool = false) {
        self.snap = payload.snapshot
        self.payload = payload
        self.family = family
        self.inlineChoices = inlineChoices
        self.inlinePicker = inlinePicker
    }

    /// The Card style paints the body; the rail keeps the mode's colour and its own ink.
    private var look: BeaconLook { beaconLook(cardStyle) }
    private var fill: Color { Color(argb: snap.tone.fillARGB) }
    private var ink: Color { Color(argb: snap.tone.inkARGB) }
    private var surfaceInk: Color { Color(argb: look.ink) }
    private var isSetup: Bool { snap.setup }
    private var isOff: Bool { snap.mode.caseInsensitiveCompare("Off") == .orderedSame }
    private var stale: Bool { snap.stale }
    private var textScale: CGFloat { look.textScale }
    private var selectionRevision: String { snap.evidence?.origin?.selectionRevision ?? "" }
    private var observedMode: String {
        snap.evidence.flatMap { $0.readings[$0.entityID] }.flatMap { ClimateState.fromJson($0.json)?.mode } ?? ""
    }

    public var body: some View {
        Group {
            if family == .systemSmall {
                // Snapshot-only entries are inert gallery/WidgetKit placeholders.
                ThermostatSmallCard(payload: payload ?? ThermostatParityInputs.payload("auto"))
            } else if let payload, family == .systemMedium, dynamicType >= .xxxLarge {
                ThermostatFocusedCard(payload: payload)
            } else {
                ordinaryBody
            }
        }
    }

    private var ordinaryBody: some View {
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
            .background(CardSurfaceView(look.body))
        }
    }

    // MARK: Left — readings
    private func left(compact: Bool) -> some View {
        // At 155pt with humidity and all three sensors: 43+15+15+15+3+3×16+14 = 153pt.
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(snap.roomTemp).font(.system(size: 36 * textScale, weight: .heavy)).tracking(-1).foregroundStyle(ink)
                    .lineLimit(1)
                Spacer(minLength: 0)
                Image(systemName: "thermometer.medium").font(HearthFont.groupLabel.font).foregroundStyle(ink.opacity(0.9))
            }
            .frame(height: 43, alignment: .leading)
            Text(snap.roomSub).font(HearthFont.footnote.font(scale: textScale).weight(.medium)).foregroundStyle(ink)
                .lineLimit(1).frame(height: 15, alignment: .leading)
            if let h = snap.humidity {
                Text(h).font(HearthFont.footnote.font(scale: textScale)).foregroundStyle(ink.opacity(0.82)).lineLimit(1)
                    .frame(height: 15, alignment: .leading)
            }
            Text(snap.commandFeedback ?? snap.status).font(HearthFont.footnote.font(scale: textScale)).foregroundStyle(ink.opacity(0.82)).lineLimit(1)
                .frame(height: 15, alignment: .leading)
                .accessibilityLabel(snap.commandError ?? snap.error ?? snap.commandFeedback ?? snap.status)
            Rectangle().fill(ink.opacity(0.26)).frame(height: 1).padding(.vertical, compact ? 1 : 2)
            ForEach(snap.sensors.prefix(3), id: \.id) { s in
                HStack(spacing: 3) {
                    Text(s.name).font(HearthFont.footnote.font(scale: textScale)).foregroundStyle(ink.opacity(0.82)).lineLimit(1)
                    Spacer(minLength: 2)
                    HStack(spacing: 2) {
                        if s.stale {
                            Image(systemName: "clock").font(HearthFont.caption.font).foregroundStyle(ink.opacity(0.85))
                        }
                        Text(s.value).font(HearthFont.footnote.font(scale: textScale).weight(.bold)).foregroundStyle(ink).lineLimit(1)
                    }.layoutPriority(1)
                }.frame(height: compact ? 16 : 17)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(s.name), \(s.value)\(s.stale ? ", last known" : "")")
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, HearthMetrics.mediumPadding).padding(.vertical, compact ? 7 : 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(BeaconRailBackground(fillARGB: snap.tone.fillARGB, fade: 0.9))
    }

    // MARK: Right — controls, on the body the Card style paints
    private func right(compact: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 6) {
                Text(snap.name).font(.system(size: 16 * textScale, weight: .bold)).foregroundStyle(surfaceInk).lineLimit(1)
                Spacer(minLength: 2)
                // Use the shared freshness cluster (Checked stamp + circular refresh button to its RIGHT),
                // same as Alarm/Car/ChargePoint and Android — was a bespoke header (bare icon on the left).
                BeaconFreshness(checkedAt: snap.checkedAt, kind: "com.rohit.hearth.thermostat", ink: surfaceInk,
                    thermostatSelection: snap.evidence?.origin)
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
    }

    @ViewBuilder private var middleContent: some View {
        if isSetup {
            setupCta
        } else if isOff && !stale {
            offCard
        } else if snap.heatSetpoint == nil && snap.coolSetpoint == nil {
            VStack(spacing: 3) {
                Text(stale ? "Unavailable" : snap.mode).font(HearthFont.callout.font(scale: textScale).weight(.semibold))
                if !stale {
                    Text("No temperature target").font(HearthFont.footnote.font(scale: textScale))
                        .foregroundStyle(surfaceInk.opacity(0.7)).multilineTextAlignment(.center)
                }
            }
            .foregroundStyle(surfaceInk).frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(alignment: .leading, spacing: 5) {
                if let heat = snap.heatSetpoint { setpointRow("Heat to", heat, look.heat, side: .heat) }
                if let cool = snap.coolSetpoint { setpointRow("Cool to", cool, look.cool, side: .cool) }
            }.disabled(stale)
        }
    }

    /// The Mode / Fan / Resume chip row (shared by the normal and off layouts), or the opened choices.
    @ViewBuilder private var controlRow: some View {
        if let inlineChoices { choiceRow(inlineChoices) } else { ordinaryControlRow }
    }

    private var ordinaryControlRow: some View {
        HStack(spacing: ControlChip.spacing) {
            if snap.canPickMode {
                pickerButton("mode", label: "Mode", value: snap.mode)
            } else {
                chip("Mode", snap.mode, enabled: snap.canPickMode)
            }
            if snap.hasFanControl {
                if snap.canPickFan {
                    pickerButton("fan", label: "Fan", value: snap.fan ?? "—")
                } else {
                    chip("Fan", snap.fan ?? "—", enabled: false)
                }
            }
            if snap.hasResumeControl {
                if snap.canResume {
                    Button(intent: ClimateSetpointIntent("resume", entityID: snap.entityID,
                        scope: snap.requestScope, revision: snap.climateRevision, resumeID: snap.resumeID,
                        selectionRevision: selectionRevision, expectedMode: observedMode)) {
                        chip(nil, "Resume", enabled: true)
                    }.buttonStyle(.plain)
                } else {
                    chip(nil, "Resume", enabled: false)
                }
            }
        }
    }

    /// Mode/Fan: the widget swaps this row for the choices; elsewhere the choices open in the app.
    @ViewBuilder private func pickerButton(_ kind: String, label: String, value: String) -> some View {
        if inlinePicker {
            Button(intent: ClimateInlinePickerIntent(kind, entityID: snap.entityID, scope: snap.requestScope,
                revision: snap.climateRevision, selectionRevision: selectionRevision, expectedMode: observedMode)) {
                chip(label, value, enabled: true)
            }.buttonStyle(.plain)
        } else {
            Button(intent: ClimatePickerIntent(kind, entityID: snap.entityID, scope: snap.requestScope,
                revision: snap.climateRevision, selectionRevision: selectionRevision, expectedMode: observedMode)) {
                chip(label, value, enabled: true)
            }.buttonStyle(.plain)
        }
    }

    /// One equal-width chip per option; the option in effect wears the card's tone and closes the row.
    private func choiceRow(_ choices: ThermostatInlineChoices) -> some View {
        HStack(spacing: ControlChip.spacing) {
            ForEach(choices.options) { option in
                Button(intent: ClimateInlineChoiceIntent(choices.kind, option: option.value,
                    entityID: snap.entityID, scope: snap.requestScope, revision: snap.climateRevision,
                    selectionRevision: selectionRevision)) {
                    choiceChip(option, kind: choices.kind)
                }.buttonStyle(.plain)
            }
        }
        .accessibilityIdentifier("thermostat.inline-\(choices.kind)-choices")
    }

    private func choiceChip(_ option: ThermostatInlineOption, kind: String) -> some View {
        Text(option.label).font(HearthFont.footnote.font(scale: textScale).weight(.semibold))
            .foregroundStyle(option.isCurrent ? ink : surfaceInk)
            .lineLimit(1).minimumScaleFactor(ControlChip.choiceScale)
            .padding(.horizontal, ControlChip.choiceInset)
            .frame(maxWidth: .infinity).frame(height: ControlChip.height)
            .background(option.isCurrent ? fill : Color(argb: look.chip),
                        in: RoundedRectangle(cornerRadius: ControlChip.radius))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(thermostatInlineAccessibilityLabel(kind: kind, option: option))
            .accessibilityAddTraits(option.isCurrent ? .isSelected : [])
    }

    /// Setup middle CTA — a large recessed "Set up thermostat" button filling the mid-region (Android parity).
    private var setupCta: some View {
        Text("Set up thermostat").font(HearthFont.groupLabel.font(scale: textScale).weight(.semibold)).foregroundStyle(surfaceInk)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(argb: look.chipFaint), in: RoundedRectangle(cornerRadius: 13))
    }

    /// Setup bottom action — a full-width "Connect" in place of the Mode/Fan/Resume row.
    private var connectButton: some View {
        Button(intent: HaSetupIntent(reconnect: snap.needsSignIn)) {
            Text(snap.needsSignIn ? "Sign in" : isSetup ? "Connect" : "Open Settings")
                .font(HearthFont.groupLabel.font(scale: textScale).weight(.semibold)).foregroundStyle(surfaceInk)
                .frame(maxWidth: .infinity).frame(height: 34)
                .background(Color(argb: look.chip), in: RoundedRectangle(cornerRadius: 9))
        }.buttonStyle(.plain)
    }

    /// Off middle message — a recessed card "Off / Choose a mode to turn on" (Android parity).
    private var offCard: some View {
        VStack(spacing: 3) {
            Text("Off").font(HearthFont.callout.font(scale: textScale).weight(.semibold)).foregroundStyle(surfaceInk)
            Text("Choose a mode to turn on").font(HearthFont.footnote.font(scale: textScale)).foregroundStyle(surfaceInk.opacity(0.7))
                .multilineTextAlignment(.center).lineLimit(2).minimumScaleFactor(0.8)
        }
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(argb: look.chipFaint), in: RoundedRectangle(cornerRadius: 13))
    }

    private func setpointRow(_ label: String, _ value: String, _ valueColor: UInt32, side: ClimateSide) -> some View {
        HStack(spacing: 5) {
            Text(label).font(HearthFont.footnote.font(scale: textScale)).foregroundStyle(surfaceInk).lineLimit(1).minimumScaleFactor(0.8)
            Spacer(minLength: 2)
            Button(intent: ClimateSetpointIntent("\(side.rawValue)Down", entityID: snap.entityID,
                scope: snap.requestScope, revision: snap.climateRevision, selectionRevision: selectionRevision, expectedMode: observedMode)) {
                Image(systemName: "minus.circle.fill").font(HearthFont.iconMedium.font).foregroundStyle(surfaceInk.opacity(0.85))
            }.buttonStyle(.plain).disabled(!canAdjust(side, up: false)).opacity(canAdjust(side, up: false) ? 1 : 0.4)
            Text(value).font(HearthFont.cardHeading.font(scale: textScale).weight(.semibold))
                .foregroundStyle(stale ? Color(argb: BeaconTone.offline.fillARGB) : Color(argb: valueColor))
                .lineLimit(1).frame(minWidth: 36)
            Button(intent: ClimateSetpointIntent("\(side.rawValue)Up", entityID: snap.entityID,
                scope: snap.requestScope, revision: snap.climateRevision, selectionRevision: selectionRevision, expectedMode: observedMode)) {
                Image(systemName: "plus.circle.fill").font(HearthFont.iconMedium.font).foregroundStyle(surfaceInk.opacity(0.85))
            }.buttonStyle(.plain).disabled(!canAdjust(side, up: true)).opacity(canAdjust(side, up: true) ? 1 : 0.4)
        }
    }

    private func canAdjust(_ side: ClimateSide, up: Bool) -> Bool {
        side == .heat ? (up ? snap.canAdjustHeatUp : snap.canAdjustHeatDown)
            : (up ? snap.canAdjustCoolUp : snap.canAdjustCoolDown)
    }

    private func chip(_ label: String?, _ value: String, enabled: Bool) -> some View {
        VStack(spacing: 0) {
            if let label { Text(label).font(HearthFont.caption.font(scale: textScale)).foregroundStyle(surfaceInk.opacity(0.7)) }
            Text(value).font(HearthFont.footnote.font(scale: textScale).weight(.semibold))
                .foregroundStyle(surfaceInk.opacity(enabled ? 1 : 0.82))
                .lineLimit(1).minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity).frame(height: ControlChip.height)
        .background(Color(argb: enabled ? look.chip : look.chipFaint),
                    in: RoundedRectangle(cornerRadius: ControlChip.radius))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label.map { $0 + ", " } ?? "")\(value)\(enabled ? "" : ", control unavailable")")
    }
}

/// The shared geometry of the bottom-row chips (Mode / Fan / Resume and the opened choices).
private enum ControlChip {
    static let spacing: CGFloat = 6
    static let height: CGFloat = 34
    static let radius: CGFloat = 9
    /// Up to seven modes share the row on one line, so their names may shrink further than a value chip's.
    static let choiceScale: CGFloat = 0.6
    static let choiceInset: CGFloat = 3
}

/// A Small production card, with a single entry-bound link and no mutation or refresh intent.
private struct ThermostatSmallCard: View {
    let payload: ThermostatEntryPayload
    @Environment(\.dynamicTypeSize) private var dynamicType
    @ScaledMetric(relativeTo: .largeTitle) private var roomSize: CGFloat = 40
    @ScaledMetric(relativeTo: .subheadline) private var secondarySize: CGFloat = 14
    @ScaledMetric(relativeTo: .body) private var openSize: CGFloat = 16

    private var content: ThermostatSmallContent {
        thermostatSmallContent(payload.presentation, destination: payload.destination)
    }
    private var ink: Color { Color(argb: content.focused.tone.inkARGB) }
    private var surfaceInk: Color { Color(argb: BeaconSurfaceColors.inkARGB) }

    var body: some View {
        GeometryReader { geometry in
            if let url = content.navigationURL {
                Link(destination: url) { composition(size: geometry.size) }
                    .buttonStyle(.plain)
            } else { composition(size: geometry.size) }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(thermostatSmallAccessibility(content))
        .accessibilityAddTraits(content.navigationURL == nil ? [] : .isLink)
        .accessibilityIdentifier("thermostat.production-small")
    }

    private func composition(size: CGSize) -> some View {
        ViewThatFits(in: [.horizontal, .vertical]) {
            if !dynamicType.isAccessibilitySize {
                if content.focused.context != nil {
                    standard(size: size, header: false, mode: true, context: true, target: false)
                    standard(size: size, header: false, mode: true, context: false, target: false)
                } else {
                    if content.target != nil {
                        standard(size: size, header: true, mode: true, context: false, target: true)
                    }
                    standard(size: size, header: true, mode: true, context: false, target: false)
                    standard(size: size, header: false, mode: true, context: false, target: false)
                }
                standard(size: size, header: false, mode: false, context: false, target: false)
            }
            critical(width: max(0, size.width - 22))
                .fixedSize(horizontal: false, vertical: true)
            handoff
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(11)
        .frame(width: size.width, height: size.height)
        .background(LinearGradient(colors: [Color(argb: content.focused.tone.fillARGB),
            Color(argb: content.focused.tone.fillARGB).opacity(0.86)],
            startPoint: .topLeading, endPoint: .bottomTrailing))
        .overlay(ContainerRelativeShape().strokeBorder(.white.opacity(0.24), lineWidth: 1))
    }

    private func standard(size: CGSize, header: Bool, mode: Bool, context: Bool, target: Bool) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            if header {
                HStack(spacing: 5) {
                    Image(systemName: "thermometer.medium")
                    Text(content.focused.room.name)
                }
                .font(.system(size: secondarySize, weight: .semibold))
                .fixedSize(horizontal: true, vertical: true)
                .frame(minHeight: 20, alignment: .leading)
            }
            VStack(alignment: .leading, spacing: 1) {
                room(verticalUnit: false)
                if let status = content.status {
                    Text(status).font(.system(size: secondarySize, weight: .medium)).fixedSize()
                }
                if mode, content.focused.room.value != nil {
                    Text(target ? "\(content.mode) · \(content.target ?? "")" : content.mode)
                        .font(.system(size: secondarySize, weight: .medium)).fixedSize()
                }
                if context, let reading = content.focused.context {
                    contextLine(reading)
                }
            }
            .frame(minHeight: max(0, size.height - (header ? 88 : 67)), alignment: .center)
            footer
        }
        .foregroundStyle(ink)
        .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder private func room(verticalUnit: Bool) -> some View {
        if let number = thermostatFocusedNumberText(content.focused.room, summary: true) {
            if verticalUnit {
                VStack(spacing: 1) {
                    numberText(number)
                    unitText
                }
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    numberText(number)
                    unitText
                }
            }
        } else {
            Text(content.placeholder).font(.system(size: secondarySize, weight: .semibold))
                .fixedSize(horizontal: true, vertical: true)
        }
    }
    private func numberText(_ value: String) -> some View {
        Text(value).font(.system(size: roomSize, weight: .heavy)).monospacedDigit()
            .fixedSize(horizontal: true, vertical: true)
    }
    private var unitText: some View {
        Text(content.focused.room.reportedUnit ?? "?")
            .font(.system(size: secondarySize, weight: .medium)).fixedSize()
    }
    private func contextLine(_ reading: ThermostatReadingFacet) -> some View {
        let value: String
        switch reading.value {
        case .number:
            value = (thermostatFocusedNumberText(reading, summary: true) ?? "No reading")
                + " " + (reading.reportedUnit ?? "?")
        case .text(let text): value = text
        case nil: value = reading.availability == .unavailable ? "Unavailable" : "No reading"
        }
        return HStack(spacing: 4) {
            if reading.failure != nil || reading.availability == .unavailable {
                Image(systemName: "exclamationmark")
            } else if reading.availability == .lastKnown {
                Image(systemName: "clock")
            }
            Text("\(reading.name) · \(value)")
        }
        .font(.system(size: secondarySize, weight: .medium))
        .fixedSize(horizontal: true, vertical: true)
    }
    private func critical(width: CGFloat) -> some View {
        VStack(spacing: 2) {
            room(verticalUnit: true)
            if let status = content.status {
                Text(status).font(.system(size: secondarySize, weight: .medium))
                    .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: width)
            }
        }
        .foregroundStyle(ink)
    }
    private var footer: some View {
        Text("Open").font(.system(size: openSize, weight: .semibold))
            .fixedSize(horizontal: true, vertical: true)
            .frame(maxWidth: .infinity, minHeight: 44)
            .foregroundStyle(surfaceInk)
            .background(Color(argb: BeaconSurfaceColors.graphiteARGB),
                        in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            .opacity(content.navigationURL == nil ? 0.35 : 1)
    }
    /// Deliberate bounded fallback: complete raw reading/status remains in the single link's label.
    private var handoff: some View {
        VStack(spacing: 4) {
            Image(systemName: content.statusSymbol).font(.system(size: secondarySize))
            Text("Open").font(.system(size: openSize, weight: .semibold)).fixedSize()
        }
        .foregroundStyle(surfaceInk)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(argb: BeaconSurfaceColors.graphiteARGB),
                    in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        .opacity(content.navigationURL == nil ? 0.35 : 1)
    }
}

/// The complete destination keeps the controls/readings; this card's footer only navigates.
private struct ThermostatFocusedCard: View {
    let payload: ThermostatEntryPayload
    @Environment(\.dynamicTypeSize) private var dynamicType
    @Environment(\.cardStyle) private var cardStyle
    @ScaledMetric(relativeTo: .largeTitle) private var roomSize: CGFloat = 36
    @ScaledMetric(relativeTo: .body) private var detailSize: CGFloat = 17
    @ScaledMetric(relativeTo: .subheadline) private var captionSize: CGFloat = 15
    @ScaledMetric(relativeTo: .headline) private var identitySize: CGFloat = 16

    private var content: ThermostatFocusedContent {
        thermostatFocusedContent(payload.presentation, accessibility: dynamicType.isAccessibilitySize,
            destination: payload.destination)
    }
    private var look: BeaconLook { beaconLook(cardStyle) }
    private var textScale: CGFloat { look.textScale }
    private var ink: Color { Color(argb: content.tone.inkARGB) }
    private var surfaceInk: Color { Color(argb: look.ink) }
    private var destination: URL? { thermostatReadingsURL(for: payload.destination) }

    var body: some View {
        GeometryReader { geometry in
            let split = beaconSplit(width: geometry.size.width)
            if dynamicType.isAccessibilitySize {
                accessibilityBands(size: geometry.size)
            } else {
                HStack(spacing: 0) {
                    readings
                        .frame(width: split.rail, height: geometry.size.height, alignment: .center)
                    ViewThatFits(in: .vertical) {
                        panel(showHeader: true, showTarget: true).fixedSize(horizontal: false, vertical: true)
                        panel(showHeader: true, showTarget: false).fixedSize(horizontal: false, vertical: true)
                        panel(showHeader: false, showTarget: false)
                    }
                    .padding(.horizontal, 13).padding(.top, 8).padding(.bottom, 6)
                    .frame(width: geometry.size.width - split.rail, height: geometry.size.height)
                }
                .frame(width: geometry.size.width, height: geometry.size.height)
            }
        }
        .background(CardSurfaceView(look.body))
        .accessibilityIdentifier("thermostat.readable-medium")
    }

    /// Accessibility categories use the full width for each reading without capping scaled fonts.
    private func accessibilityBands(size: CGSize) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    if content.room.value != nil, let symbol = accessibilityRoomStatusSymbol {
                        Image(systemName: symbol)
                            .font(.system(size: captionSize))
                            .fixedSize(horizontal: true, vertical: true).accessibilityHidden(true)
                    }
                    if let number = thermostatFocusedNumberText(content.room, summary: true) {
                        Text(number)
                            .font(.system(size: roomSize * textScale, weight: .heavy)).monospacedDigit()
                            .fixedSize(horizontal: true, vertical: true)
                        Text(content.room.reportedUnit ?? "?")
                            .font(.system(size: captionSize * textScale, weight: .medium))
                            .fixedSize(horizontal: true, vertical: true)
                    } else {
                        Text(accessibilityRoomPlaceholder)
                            .font(.system(size: detailSize * textScale, weight: .semibold)).lineLimit(1)
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(payload.snapshot.name). "
                    + thermostatFocusedReadingAccessibility(content.room, attribution: content.roomAttribution)
                    + ". \(content.recoveryTitle.map { $0 + ". " } ?? "")\(content.mode).")
                Spacer(minLength: 0)
                if let destination {
                    Link(destination: destination) { accessibilityChevron }
                        .accessibilityLabel("Open \(payload.snapshot.name) readings and controls")
                } else {
                    accessibilityChevron.opacity(0.35)
                        .accessibilityLabel("Example \(payload.snapshot.name). Open readings and controls inactive")
                }
            }
            .padding(.horizontal, HearthMetrics.mediumPadding)
            .frame(width: size.width, height: size.height * 0.54)
            .foregroundStyle(ink)
            .background(BeaconRailBackground(fillARGB: content.tone.fillARGB, fade: 0.9))
            Group {
                if let context = content.context {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(context.name).font(.system(size: captionSize * textScale, weight: .medium))
                            .lineLimit(1).truncationMode(.tail)
                        Spacer(minLength: 0)
                        if let symbol = accessibilityContextStatusSymbol(context) {
                            Image(systemName: symbol)
                                .font(.system(size: captionSize))
                                .fixedSize(horizontal: true, vertical: true).accessibilityHidden(true)
                        }
                        Text(accessibilityReadingValue(context)).font(.system(size: detailSize * textScale, weight: .semibold))
                            .fixedSize(horizontal: true, vertical: true)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(thermostatFocusedReadingAccessibility(context))
                } else {
                    Text("No context").font(.system(size: captionSize * textScale)).lineLimit(1)
                        .accessibilityLabel("No context selected")
                }
            }
            .padding(.horizontal, HearthMetrics.mediumPadding)
            .frame(width: size.width, height: size.height * 0.46)
            .foregroundStyle(surfaceInk)
        }
        .frame(width: size.width, height: size.height)
    }

    private var accessibilityChevron: some View {
        Image(systemName: "chevron.right")
            .font(.system(size: captionSize, weight: .semibold))
            .frame(width: 44, height: 44)
            // On the rail, which no Card style reaches: its own fixed chip.
            .background(Color.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 9))
    }

    private var accessibilityRoomStatusSymbol: String? {
        if payload.presentation.recovery != .none { return "exclamationmark.circle" }
        switch payload.presentation.operation {
        case .pending: return "arrow.triangle.2.circlepath"
        case .failed: return "exclamationmark.circle"
        case .none:
            return content.room.availability == .lastKnown ? "clock" : nil
        }
    }

    private var accessibilityRoomPlaceholder: String {
        switch payload.presentation.recovery {
        case .setup: return "Set up"
        case .authentication: return "Sign in"
        default: return "No reading"
        }
    }

    private func accessibilityContextStatusSymbol(_ context: ThermostatReadingFacet) -> String? {
        if context.failure != nil || context.availability == .unavailable { return "exclamationmark" }
        return context.availability == .lastKnown ? "clock" : nil
    }

    private func accessibilityReadingValue(_ reading: ThermostatReadingFacet) -> String {
        switch reading.value {
        case .number:
            return (thermostatFocusedNumberText(reading, summary: true) ?? "—")
                + " " + (reading.reportedUnit ?? "?")
        case .text(let text): return text
        case nil: return "—"
        }
    }

    private var readings: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let number = thermostatFocusedNumberText(content.room, summary: true) {
                Text(number)
                    .font(.system(size: roomSize * textScale, weight: .heavy)).monospacedDigit()
                    .fixedSize(horizontal: true, vertical: true)
                Text("\(content.roomAttribution) · \(content.room.reportedUnit ?? "Unit not reported")")
                    .font(.system(size: captionSize * textScale, weight: .medium))
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text(content.roomAttribution).font(.system(size: detailSize * textScale, weight: .semibold))
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let context = content.context {
                VStack(alignment: .leading, spacing: 2) {
                    Text(context.name).font(.system(size: captionSize * textScale, weight: .medium))
                    Text(readingValue(context)).font(.system(size: detailSize * textScale, weight: .semibold))
                    if context.availability == .lastKnown {
                        Text("Last known").font(.system(size: captionSize * textScale))
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(thermostatFocusedReadingAccessibility(context))
            } else {
                Text("No context selected").font(.system(size: captionSize * textScale))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, HearthMetrics.mediumPadding).padding(.vertical, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .foregroundStyle(ink)
        .background(BeaconRailBackground(fillARGB: content.tone.fillARGB, fade: 0.9))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(payload.snapshot.name). "
            + thermostatFocusedReadingAccessibility(content.room, attribution: content.roomAttribution) + ". "
            + (content.context.map { thermostatFocusedReadingAccessibility($0) } ?? "No context selected."))
    }

    private func panel(showHeader: Bool, showTarget: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if showHeader {
                HStack(alignment: .top, spacing: 6) {
                    Text(payload.snapshot.name).font(.system(size: identitySize * textScale, weight: .bold)).lineLimit(1)
                    Spacer(minLength: 2)
                    BeaconFreshness(checkedAt: payload.snapshot.checkedAt, kind: "com.rohit.hearth.thermostat",
                        ink: surfaceInk, interactionsEnabled: payload.destination != .inert,
                        thermostatSelection: payload.presentation.origin)
                }
            }
            Spacer(minLength: 0)
            VStack(alignment: .leading, spacing: 4) {
                Text(content.recoveryTitle ?? content.mode)
                    .font(.system(size: detailSize * textScale, weight: .semibold))
                    .fixedSize(horizontal: false, vertical: true)
                if content.recoveryTitle != nil {
                    Text(content.mode).font(.system(size: captionSize * textScale))
                        .fixedSize(horizontal: false, vertical: true)
                }
                if showTarget, let target = content.target {
                    Text(target).font(.system(size: detailSize * textScale))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .accessibilityElement(children: .combine)
            Spacer(minLength: 0)
            if let destination {
                Link(destination: destination) { openLabel }
                    .accessibilityLabel("Open \(payload.snapshot.name) readings and controls")
            } else {
                openLabel.accessibilityLabel("Example \(payload.snapshot.name). Open readings and controls inactive")
            }
        }
        .foregroundStyle(surfaceInk)
    }

    private var openLabel: some View {
        HStack(spacing: 5) {
            Text(content.footerLabel).font(.system(size: detailSize * textScale, weight: .semibold))
            Image(systemName: "chevron.right").font(.system(size: captionSize)).accessibilityHidden(true)
        }
        .padding(.horizontal, 8).padding(.vertical, 6)
        .frame(maxWidth: .infinity, minHeight: 44)
        .background(Color(argb: look.chip), in: RoundedRectangle(cornerRadius: 9))
    }

    private func readingValue(_ reading: ThermostatReadingFacet) -> String {
        switch reading.value {
        case .number:
            let formatted = thermostatFocusedNumberText(reading, summary: true) ?? "No reading"
            return formatted + (reading.reportedUnit.map { " \($0)" } ?? " · Unit not reported")
        case .text(let text): return text
        case nil: return reading.availability == .unavailable ? "Unavailable" : "No reading"
        }
    }

}
