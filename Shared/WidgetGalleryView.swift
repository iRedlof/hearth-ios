import SwiftUI
import UIKit
import WidgetKit
import HearthKit

/// An inert production-view example at an approximate phone reference size.
/// This is an in-app layout preview, not a WidgetKit Home Screen snapshot.
struct WidgetGalleryView: View {
    @State private var kind: WidgetPreviewKind?
    @State private var reference: PhoneReference = .large
    @State private var family: WidgetPreviewFamily = .medium
    @State private var examples = WidgetPreviewExampleSelection()
    @Environment(\.dynamicTypeSize) private var dynamicType
    @State private var activitySample = ActivitySnapshot.sample
    @ScaledMetric(relativeTo: .body) private var collectionTextScale: CGFloat = 1
    @State private var exampleReferenceTime = Date()
    private let unsupportedInitialKind: String?

    init() {
        let requested = UserDefaults.standard.string(forKey: "widget") ?? "car"
        let selected = WidgetPreviewKind(rawValue: requested)
        _kind = State(initialValue: selected)
        unsupportedInitialKind = selected == nil ? requested : nil
    }

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Widget previews")
                        .font(.title2.weight(.semibold))
                    selectors
                    if let kind {
                        specimen(kind, availableWidth: max(1, geometry.size.width - 40))
                    } else {
                        VStack(alignment: .leading, spacing: 8) {
                            if let unsupportedInitialKind {
                                Text("No preview is available for “\(unsupportedInitialKind)”.")
                            }
                            Text("Choose a widget to see its designed layout.")
                                .foregroundStyle(.secondary)
                        }
                        .font(.body)
                        .accessibilityIdentifier("widget.preview.unavailable")
                    }
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
        .accessibilityIdentifier("widget.previews")
        .onChange(of: kind) { _, selected in family = selected?.family ?? .medium }
    }

    private var selectors: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Widget").font(.subheadline).foregroundStyle(.secondary)
            Menu {
                Picker("Widget", selection: $kind) {
                    if kind == nil {
                        Text("Choose a widget").tag(Optional<WidgetPreviewKind>.none)
                    }
                    ForEach(WidgetPreviewKind.allCases) { item in
                        Label(item.title, systemImage: item.symbolName).tag(Optional(item))
                    }
                }
            } label: {
                selectorLabel(kind?.title ?? "Choose a widget", symbol: kind?.symbolName)
            }
            .accessibilityLabel("Widget")
            .accessibilityValue(kind?.title ?? "None selected")
            .accessibilityIdentifier("widget.preview.kind")

            if let kind {
                let selected = examples.selected(for: kind)
                let choices = widgetPreviewExamples(for: kind)
                let groups = choices.reduce(into: [String]()) { result, item in
                    if !result.contains(item.group) { result.append(item.group) }
                }
                Text("Example state")
                    .font(.subheadline).foregroundStyle(.secondary).padding(.top, 8)
                Menu {
                    Picker("Example state", selection: Binding(
                        get: { examples.selected(for: kind).id },
                        set: { examples.select(id: $0, for: kind) })) {
                        ForEach(groups, id: \.self) { group in
                            Section(group) {
                                ForEach(choices.filter { $0.group == group }) { example in
                                    Text(example.title).tag(example.id)
                                }
                            }
                        }
                    }
                } label: {
                    selectorLabel(selected.title, symbol: nil)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityLabel("Example state")
                .accessibilityValue(selected.title)
                .accessibilityHint("Changes the illustrative example. Does not change your widget or account.")
                .accessibilityIdentifier("widget.preview.state")
            }

            if let kind, kind.supportedFamilies.count > 1 {
                Text("Widget size").font(.subheadline).foregroundStyle(.secondary).padding(.top, 8)
                Menu {
                    Picker("Widget size", selection: $family) {
                        ForEach(kind.supportedFamilies, id: \.self) { item in
                            Text("\(item.title) widget").tag(item)
                        }
                    }
                } label: {
                    selectorLabel("\(selectedFamily(for: kind).title) widget", symbol: "square")
                }
                .accessibilityLabel("Widget size")
                .accessibilityValue("\(selectedFamily(for: kind).title) widget")
                .accessibilityIdentifier("widget.preview.family")
            }

            Text("Phone reference")
                .font(.subheadline).foregroundStyle(.secondary).padding(.top, 8)
            Menu {
                Picker("Phone reference", selection: $reference) {
                    ForEach(PhoneReference.allCases) { item in
                        Text(item.title).tag(item)
                    }
                }
            } label: {
                selectorLabel(reference.title, symbol: "iphone")
            }
            .accessibilityLabel("Phone reference")
            .accessibilityValue(reference.title)
            .accessibilityIdentifier("widget.preview.reference")
        }
    }

    private func selectorLabel(_ title: String, symbol: String?) -> some View {
        HStack(spacing: 12) {
            if let symbol {
                Image(systemName: symbol)
                    .font(.system(size: 20, weight: .regular))
                    .symbolRenderingMode(.monochrome)
                    .frame(width: 24, height: 24)
            }
            Text(title).font(.body)
            Spacer(minLength: 8)
            Image(systemName: "chevron.up.chevron.down")
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(.secondary)
        }
        .foregroundStyle(.primary)
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, minHeight: 48)
        .background(Color(uiColor: .secondarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func specimen(_ kind: WidgetPreviewKind, availableWidth: CGFloat) -> some View {
        let selectedFamily = selectedFamily(for: kind)
        let size = reference.size(for: selectedFamily)
        let scale = min(1, availableWidth / size.width)
        let percentage = Int((scale * 100).rounded())
        let selected = examples.selected(for: kind)
        let projection = projectedExample(kind, id: selected.id, family: selectedFamily, size: size)
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Text(kind.title).font(.headline)
                Spacer(minLength: 0)
                Text("Example data")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Text(selected.title)
                .font(.body)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("widget.preview.stateCaption")
            Text("\(selectedFamily.title) widget · approximately \(Int(size.width)) × \(Int(size.height)) pt")
                .font(.body).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text(projection.facts)
                .font(.body).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("widget.preview.stateSummary")
            if let disclosure = projection.disclosure {
                Text(disclosure).font(.body).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            InertWidgetPreview(content: projection.card)
                .frame(width: size.width, height: size.height)
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                .scaleEffect(scale)
                .frame(width: size.width * scale, height: size.height * scale)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
                .focusable(false)
                .frame(maxWidth: .infinity, alignment: .center)

            Text("Illustrative sample, not your account or a live reading. Preview controls are inactive.")
                .font(.body).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("widget.preview.inactive")
            Text("Shown at \(percentage)% to fit this screen, with the full layout in proportion. Preview controls are inactive.")
                .font(.body).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("widget.preview.scale")
            Text("Home Screen dimensions and rounded corners are applied by WidgetKit and may differ from this in-app example.")
                .font(.body).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if kind == .car {
                Text("At larger text sizes, Car prioritizes its main status and Readings. The photo, detailed readings and controls are in the readings screen.")
                    .font(.body).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityIdentifier("widget.preview.example")
    }

    /// The selected builder runs once per projection; caption, facts and card share its input.
    private struct ExampleProjection {
        let card: AnyView
        let facts: String
        var disclosure: String? = nil
    }

    private func words(_ values: [String?]) -> String {
        values.compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ". ")
    }

    private func checked(_ stamp: String, historical: Bool = false) -> String? {
        stamp.isEmpty ? nil : "\(historical ? "Last checked" : "Checked") \(stamp)"
    }

    private func tileStatus(_ state: TileSnapshotState, error: String?, choice: String, empty: String) -> String? {
        switch state {
        case .setup: "Connect Home Assistant"
        case .loading: "Checking"
        case .choose: choice
        case .empty: empty
        case .failed: error ?? "Could not load reading"
        case .ready: error
        }
    }

    private func projectedExample(_ kind: WidgetPreviewKind, id: String,
                                  family: WidgetPreviewFamily, size: CGSize) -> ExampleProjection {
        switch kind {
        case .car:
            let payload = CarParityInputs.productionPayload(id, destination: .inert)
            let content = carSmallContent(payload)
            // Small and enlarged Medium deliberately hand off additional details.
            let compact = family == .small || dynamicType >= .xxxLarge
            let snap = payload.snapshot
            let facts: String
            if family == .medium && dynamicType >= .xxxLarge {
                // Enlarged Medium suppresses secondary battery, openings and checked time.
                facts = payload.readingsUnavailable ? "Not saved" : carPrimarySummary(payload.primary)
            } else if compact {
                facts = words(content.criticalTexts.map(Optional.init) +
                    [content.battery.map { "Battery \($0)" }, content.openingDetail,
                     content.openingsUnknown ? "Openings unknown" : nil])
            } else {
                facts = words([snap.name, snap.chargeLine, snap.battery.map { "Battery \($0)%" },
                               snap.lock, snap.doors, snap.place, snap.error,
                               checked(snap.checkedAt, historical: snap.stale)])
            }
            return ExampleProjection(card: AnyView(CarWidgetPresentation(payload: payload,
                family: family.widgetKitFamily)), facts: facts,
                disclosure: compact ? "These are the selected primary example facts. Small may reduce to an inactive Readings handoff when text cannot fit; enlarged Medium shows only its main answer. Additional readings and controls are not shown here." : nil)
        case .alarm:
            let snap = AlarmParityInputs.snapshot(id)
            let compact = family == .small
            let content = alarmSmallContent(snap)
            let facts = compact ? words(content.criticalTexts.map(Optional.init)) :
                words([snap.stateWord, snap.detail, snap.doorSelected ? "\(snap.doorName): \(snap.doorState)" : nil,
                       snap.doorSince, snap.error, snap.doorError, snap.commandFeedback, snap.commandError,
                       snap.actions.isEmpty ? nil : "Displayed actions: " + snap.actions.map(\.label).joined(separator: ", "),
                       checked(snap.checkedAt, historical: snap.stale)])
            return ExampleProjection(card: AnyView(AlarmBeaconView(snap, family: family.widgetKitFamily)),
                facts: facts, disclosure: compact ? "These are the selected primary example facts. Small may reduce to an inactive Open handoff when text cannot fit. Companion detail, dates and action meanings belong to Medium." : nil)
        case .thermostat:
            let payload = ThermostatParityInputs.payload(id)
            let snap = payload.snapshot
            let focused = thermostatSmallContent(payload.presentation, destination: .inert)
            let compact = family == .small || (family == .medium && dynamicType >= .xxxLarge)
            let facts = compact ? words([thermostatFocusedReadingAccessibility(focused.focused.room,
                attribution: focused.focused.roomAttribution), focused.status, focused.mode]) :
                words([snap.roomTemp, snap.roomSub, "Mode: \(snap.mode)", snap.status,
                       snap.heatSetpoint.map { "Heat target \($0)" }, snap.coolSetpoint.map { "Cool target \($0)" },
                       snap.fan.map { "Fan \($0)" }, snap.error,
                       checked(snap.checkedAt, historical: snap.stale)])
            return ExampleProjection(card: AnyView(ThermostatBeaconView(payload, family: family.widgetKitFamily)),
                facts: facts, disclosure: compact ? "These are the selected primary example facts. Small may reduce to an inactive Readings handoff when text cannot fit. Additional targets, sensors and controls are not guaranteed to be shown in this family or text size." : nil)
        case .chargepoint:
            guard let example = CpWidgetPreviewExample(rawValue: id) else {
                return ExampleProjection(card: AnyView(Text("Example unavailable")), facts: "Example unavailable")
            }
            let snap = cpWidgetPreviewSnapshot(example, now: exampleReferenceTime)
            let pending = example == .busy_snooze || example == .held_pending
            var facts: [String?] = [
                snap.bigAnswer, snap.unit, pending ? snap.statusDescription : snap.sub,
                "Account: \(snap.account)", snap.site,
                snap.autoOn ? "Auto on" : "Auto off",
                example == .held_unknown ? "Allowance unknown" : nil
            ]
            facts.append(contentsOf: snap.railNotes.map { Optional($0) })
            if pending {
                facts.append("Inactive footer meanings: \(snap.keys.map(\.label).joined(separator: ", "))")
            } else {
                facts.append(contentsOf: snap.keys.map { Optional("Displayed action: \($0.label)") })
            }
            facts.append(checked(snap.checkedAt))
            return ExampleProjection(card: AnyView(CpBeaconView(snap)), facts: words(facts),
                disclosure: pending ? "Illustrative request feedback. No request was sent." : nil)
        case .lights:
            let snap: LightsSnapshot = id == "sample" ? .sample : TileParityInputs.lights(id)
            let page = lightTilePage(snap.summary)
            let status = tileStatus(snap.state, error: snap.error, choice: "", empty: "No lights found")
            let rows = status == nil ? page.main.map { lightFact($0) } +
                page.pinned.map { "Always show " + lightFact($0) } : []
            return ExampleProjection(card: AnyView(LightTileView(snap)), facts: words(
                [status ?? snap.summary.headline] + rows.map(Optional.init) +
                [status == nil && page.hiddenCount > 0 ? "+\(page.hiddenCount) more" : nil, checked(snap.checkedAt)]))
        case .favourites:
            let snap: FavSnapshot = id == "sample" ? .sample : TileParityInputs.favourites(id)
            let rows = snap.items.prefix(4).map { "\($0.name): \(!$0.available ? "Unavailable" : $0.domain == "script" ? "Run" : $0.on ? "On" : "Off")" }
            return ExampleProjection(card: AnyView(FavouritesView(snap)), facts: words(
                [tileStatus(snap.state, error: snap.error, choice: "Choose your favourites", empty: "No favourites found")] +
                rows.map(Optional.init) + [snap.items.count > 4 ? "+\(snap.items.count - 4) more" : nil, checked(snap.checkedAt)]))
        case .quick:
            let snap: QuickSnapshot = id == "sample" ? .sample : TileParityInputs.quick(id)
            return ExampleProjection(card: AnyView(QuickView(snap)), facts: words(
                [tileStatus(snap.state, error: snap.error, choice: "Choose your scripts", empty: "No scripts found")] +
                snap.keys.prefix(4).map { "\($0.name): \($0.available ? "Run" : "Unavailable")" } +
                [snap.keys.count > 4 ? "+\(snap.keys.count - 4) more" : nil]))
        case .doors:
            let snap: DoorsSnapshot = id == "sample" ? .sample : CollectionParityInputs.doors(id)
            let summary = doorsCommandPresentation(snap.summary, operation: snap.operation)
            let scale = max(1, Double(collectionTextScale))
            let identityWidth = max(0, Double(size.width) - 30 - 20 - 20 - 9 - (5 * 14 * scale + 24) - 8)
            let identities = doorRowIdentities(snap.summary.rows, nameCapacity: Int(identityWidth / (14 * scale)),
                detailCapacity: Int(identityWidth / (12 * scale * 0.62)))
            let priorityID = snap.summary.rows.first {
                identities[$0.id]?.identifiable == true && displayedDoorAction($0, snapshot: snap) == .stop
            }?.id
            let layout = doorsCollectionLayout(width: Double(size.width), height: Double(size.height), fontScale: scale,
                rows: snap.summary.rows, hasError: snap.error != nil, priorityID: priorityID)
            let shown = layout.priorityID.flatMap { id in snap.summary.rows.first { $0.id == id }.map { [$0] } }
                ?? (layout.budget.summaryOnly ? [] : Array(snap.summary.rows.prefix(layout.budget.count)))
            let rows = shown.map { row -> String in
                let pending = snap.operation.flatMap { operation in
                    operation.pending && operation.entityID == row.id ? DoorAction(rawValue: operation.action)?.pending : nil
                }
                return "\(row.name): \(pending ?? row.status)"
            }
            let headerVisible = layout.priorityID == nil && !layout.budget.summaryOnly
            let headline: String
            switch snap.state {
            case .setup: headline = "Set up Home Assistant"
            case .choose: headline = "Choose doors"
            case .loading: headline = "Loading doors"
            case .failed: headline = snap.summary.rows.isEmpty ? "Can't read doors" : summary.headline
            default: headline = summary.headline
            }
            return ExampleProjection(card: AnyView(DoorsView(snap)), facts: words(
                [headerVisible ? headline : nil, headerVisible ? snap.error : nil] + rows.map(Optional.init) +
                layout.lines.map(Optional.init) + [headerVisible ? checked(snap.checkedAt, historical: snap.error != nil) : nil]),
                disclosure: snap.operation != nil ? "This example request is not a confirmed physical result. Preview controls are inactive." : nil)
        case .activity:
            let snap = id == "sample" ? activitySample : CollectionParityInputs.activity(id)
            let now = id == "sample" ? exampleReferenceTime : CollectionParityInputs.now
            let items = activityInWindow(snap.items, now: now)
            let headline = activitySnapshotHeadline(snap, now: now)
            let checkedText = checked(snap.checkedAt, historical: snap.error != nil)
            let layout = activityLayout(width: Double(size.width), height: Double(size.height),
                fontScale: Double(collectionTextScale), items: items, hasError: snap.error != nil,
                now: now, headline: headline, checkedText: checkedText)
            let rows = layout.shown.map { item in
                words([item.text, activityTimeLabel(item.at, now: now), item.by.map { "by \($0)" }])
            }
            let facts = layout.summaryOnly ? words([layout.showSummaryTitle ? (snap.error != nil ? "Unavailable" : "Activity") : nil,
                layout.summaryLabel, layout.checkedLines > 0 ? layout.checkedText : nil]) :
                words([headline, snap.error, layout.checkedLines > 0 ? layout.checkedText : nil] +
                rows.map(Optional.init) + [layout.hiddenCount > 0 ? "+\(layout.hiddenCount) more events" : nil])
            return ExampleProjection(card: AnyView(ActivityView(snap, now: now)), facts: facts)
        case .battery:
            let snap: BatterySnapshot = id == "sample" ? .sample : CollectionParityInputs.batteries(id)
            let budget = batteryCollectionBudget(width: Double(size.width), height: Double(size.height),
                fontScale: Double(collectionTextScale), rows: snap.summary.rows,
                hasError: snap.error != nil, compact: family == .medium)
            let headline: String
            switch snap.state {
            case .setup: headline = "Connect"
            case .choose: headline = "Choose batteries"
            case .loading: headline = "Checking…"
            case .failed: headline = snap.summary.rows.isEmpty ? "No reading" : "Last reading"
            default: headline = snap.summary.headline
            }
            let header: String?
            switch budget.headerMode {
            case .none: header = nil
            case .compact: header = snap.state == .failed ? "Last read" : "Batteries"
            case .full: header = words(["Batteries", headline])
            }
            var facts: [String?] = [header]
            if snap.summary.rows.isEmpty {
                let status: String
                switch snap.state {
                case .setup: status = "Connect Home Assistant"
                case .choose: status = "Choose batteries"
                case .loading: status = "Checking…"
                case .failed: status = "Couldn't read your home"
                case .ready, .empty: status = "No batteries found"
                }
                facts.append(status)
                facts.append(snap.error)
                if snap.state == .setup || snap.state == .choose || beaconNeedsSettings(snap.error) {
                    facts.append(snap.state == .choose ? "Displayed action: Open Settings" : "Displayed action: Connect")
                }
            } else {
                facts.append(contentsOf: snap.summary.rows.prefix(budget.rows).map {
                    Optional("\($0.name): \($0.readingLabel)")
                })
                if budget.showOverflow {
                    facts.append(contentsOf: budget.overflowLines.map { Optional($0) })
                }
                if budget.showError { facts.append(snap.error) }
            }
            if budget.headerMode == .full && !snap.checkedAt.isEmpty {
                facts.append("\(snap.state == .failed ? "Last read" : "Checked") \(snap.checkedAt)")
            }
            return ExampleProjection(card: AnyView(BatteryView(snap, layoutFamily: family.widgetKitFamily)),
                facts: words(facts))

        }
    }

    private func lightFact(_ row: LightView) -> String {
        words(["\(row.name): \(row.tile)", row.percent.map { "\($0)%" }])
    }

    private func carPrimarySummary(_ primary: CarReadingsPrimary) -> String {
        switch primary {
        case .setup: "Set up"
        case .signIn: "Sign in"
        case .noCar: "No car"
        case .changed: "Changed"
        case .unidentified: "Unknown"
        case .identityMismatch: "Check car"
        case .storageUnavailable, .readFailed, .noReading: "No reading"
        case .lastKnown(let authenticationRequired): authenticationRequired ? "Sign in" : "Last known"
        case .openings: "Open"
        case .unlocked: "Unlocked"
        case .tireWarning: "Check tires"
        case .lowBattery: "Low battery"
        case .charging(let starting): starting ? "Starting" : "Charging"
        case .battery(let value): value.isFinite && (0...100).contains(value) ? "\(Int(value.rounded()))%" : "No reading"
        }
    }

    private func displayedDoorAction(_ row: DoorView, snapshot: DoorsSnapshot) -> DoorAction? {
        if snapshot.doors.first(where: { $0.id == row.id })?.supportsStop == false,
           row.action == .stop || snapshot.operation?.pending == true && snapshot.operation?.entityID == row.id { return nil }
        guard let operation = snapshot.operation, operation.pending else { return row.action }
        guard operation.entityID == row.id, row.id.hasPrefix("cover."),
              ["open", "close"].contains(operation.action) else { return nil }
        return .stop
    }

    private func selectedFamily(for kind: WidgetPreviewKind) -> WidgetPreviewFamily {
        kind.supportedFamilies.contains(family) ? family : kind.family
    }

    private enum PhoneReference: String, CaseIterable, Identifiable {
        case small
        case large

        var id: String { rawValue }
        var title: String {
            switch self {
            case .small: "Small iPhone reference"
            case .large: "Large iPhone reference"
            }
        }
        func size(for family: WidgetPreviewFamily) -> CGSize {
            switch (self, family) {
            case (.small, .small): CGSize(width: 155, height: 155)
            case (.large, .small): CGSize(width: 164 + 1.0 / 3, height: 164 + 1.0 / 3)
            case (.small, .medium): CGSize(width: 329, height: 155)
            case (.small, .large): CGSize(width: 329, height: 345)
            case (.large, .medium): CGSize(width: 364, height: 170)
            case (.large, .large): CGSize(width: 364, height: 382)
            }
        }
    }
}

/// Blocks preview input at the native host without changing the production controls' enabled look.
private struct InertWidgetPreview<Content: View>: UIViewControllerRepresentable {
    let content: Content

    func makeUIViewController(context: Context) -> InertWidgetPreviewController {
        let controller = InertWidgetPreviewController(rootView: rootView(context: context))
        controller.safeAreaRegions = []
        controller.view.backgroundColor = .clear
        controller.view.isUserInteractionEnabled = false
        controller.view.accessibilityElementsHidden = true
        return controller
    }

    func updateUIViewController(_ controller: InertWidgetPreviewController, context: Context) {
        controller.rootView = rootView(context: context)
    }

    private func rootView(context: Context) -> AnyView {
        AnyView(content
            .environment(\.colorScheme, context.environment.colorScheme)
            .environment(\.dynamicTypeSize, context.environment.dynamicTypeSize)
            .environment(\.layoutDirection, context.environment.layoutDirection)
            .allowsHitTesting(false)
            .accessibilityHidden(true))
    }
}

private final class InertWidgetPreviewController: UIHostingController<AnyView> {
    override var canBecomeFirstResponder: Bool { false }
    override var keyCommands: [UIKeyCommand]? { [] }
    override func shouldUpdateFocus(in context: UIFocusUpdateContext) -> Bool { false }
}

/// UI adapter only; family membership lives in the platform-independent catalog.
extension WidgetPreviewFamily {
    var widgetKitFamily: WidgetFamily {
        switch self {
        case .small: .systemSmall
        case .medium: .systemMedium
        case .large: .systemLarge
        }
    }
}

extension WidgetPreviewKind {
    var widgetKitFamilies: [WidgetFamily] { supportedFamilies.map(\.widgetKitFamily) }
}

#Preview { WidgetGalleryView() }
