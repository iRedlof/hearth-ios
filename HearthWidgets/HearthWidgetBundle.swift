import WidgetKit
import SwiftUI
import HearthKit

@main
struct HearthWidgetBundle: WidgetBundle {
    var body: some Widget {
        CarWidget()
        AlarmWidget()
        ThermostatWidget()
        ChargePointWidget()
        BatteryWidget()
        ActivityWidget()
        LightsWidget()
        QuickWidget()
        FavouritesWidget()
        DoorsWidget()
        #if DEBUG
        SmallConceptWidget()
        ReadableConceptWidget()
        CarReadingsRouteProbeWidget(slot: .a)
        CarReadingsRouteProbeWidget(slot: .b)
        #endif
    }
}

// MARK: - Batteries

struct BatteryEntry: TimelineEntry { let date: Date; let snap: BatterySnapshot }

struct BatteryProvider: TimelineProvider {
    func placeholder(in context: Context) -> BatteryEntry { BatteryEntry(date: .now, snap: .sample) }
    func getSnapshot(in context: Context, completion: @escaping (BatteryEntry) -> Void) {
        if context.isPreview { completion(BatteryEntry(date: .now, snap: .sample)); return }
        nonisolated(unsafe) let completion = completion
        Task { completion(BatteryEntry(date: .now, snap: await Self.fetch())) }
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<BatteryEntry>) -> Void) {
        nonisolated(unsafe) let completion = completion
        Task {
            let snap = await BatteryProvider.fetch()
            completion(Timeline(entries: [BatteryEntry(date: .now, snap: snap)],
                                policy: .after(Date().addingTimeInterval(60 * 60))))   // batteries move slowly → hourly
        }
    }
    private static func fetch() async -> BatterySnapshot {
        #if DEBUG
        if ParityCatalog.activeWidgetID(prefix: "battery") != nil { return .loading }
        #endif
        return await CollectionLiveSnapshots.batteries()
    }
}

struct BatteryWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "com.rohit.hearth.battery", provider: BatteryProvider()) { entry in
            ParityWidgetContent(prefix: "battery") { BatteryView(entry.snap) }
                .containerBackground(for: .widget) { Color(argb: entry.snap.summary.tone.fillARGB) }
        }
        .configurationDisplayName("Batteries")
        .description("Every battery you replace, lowest first.")
        .supportedFamilies(WidgetPreviewKind.battery.widgetKitFamilies)
        .contentMarginsDisabled()
    }
}

// MARK: - Activity

struct ActivityEntry: TimelineEntry { let date: Date; let snap: ActivitySnapshot }

struct ActivityProvider: TimelineProvider {
    func placeholder(in context: Context) -> ActivityEntry { ActivityEntry(date: .now, snap: .sample) }
    func getSnapshot(in context: Context, completion: @escaping (ActivityEntry) -> Void) {
        if context.isPreview { completion(ActivityEntry(date: .now, snap: .sample)); return }
        nonisolated(unsafe) let completion = completion
        Task { completion(ActivityEntry(date: .now, snap: await Self.fetch())) }
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<ActivityEntry>) -> Void) {
        nonisolated(unsafe) let completion = completion
        Task {
            let snap = await ActivityProvider.fetch()
            completion(Timeline(entries: [ActivityEntry(date: .now, snap: snap)],
                                policy: .after(Date().addingTimeInterval(15 * 60))))
        }
    }
    private static func fetch() async -> ActivitySnapshot {
        #if DEBUG
        if ParityCatalog.activeWidgetID(prefix: "activity") != nil { return .loading }
        #endif
        return await CollectionLiveSnapshots.activity()
    }
}

struct ActivityWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "com.rohit.hearth.activity", provider: ActivityProvider()) { entry in
            ParityWidgetContent(prefix: "activity") { ActivityView(entry.snap) }
                .containerBackground(for: .widget) { Color(argb: DoorsTone.unknown.fillARGB) }
        }
        .configurationDisplayName("Activity")
        .description("Recent home events — doors, locks, alarm.")
        .supportedFamilies(WidgetPreviewKind.activity.widgetKitFamilies)
        .contentMarginsDisabled()
    }
}

// MARK: - Lights

struct LightsEntry: TimelineEntry { let date: Date; let snap: LightsSnapshot }

struct LightsProvider: TimelineProvider {
    func placeholder(in context: Context) -> LightsEntry { LightsEntry(date: .now, snap: .sample) }
    func getSnapshot(in context: Context, completion: @escaping (LightsEntry) -> Void) {
        if context.isPreview { completion(LightsEntry(date: .now, snap: .sample)); return }
        nonisolated(unsafe) let completion = completion
        Task { completion(LightsEntry(date: .now, snap: await Self.fetch())) }
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<LightsEntry>) -> Void) {
        nonisolated(unsafe) let completion = completion
        Task {
            let snap = await LightsProvider.fetch()
            completion(Timeline(entries: [LightsEntry(date: .now, snap: snap)],
                                policy: .after(Date().addingTimeInterval(15 * 60))))
        }
    }
    private static func fetch() async -> LightsSnapshot {
        #if DEBUG
        if ParityCatalog.activeWidgetID(prefix: "lights") != nil { return .loading }
        #endif
        return await fetchLightsSnapshot(HaConfigStore.load())
    }
}

struct LightsWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "com.rohit.hearth.lights", provider: LightsProvider()) { entry in
            ParityWidgetContent(prefix: "lights") { LightTileView(entry.snap) }
                .containerBackground(for: .widget) { Color(argb: BeaconSurfaceColors.graphiteARGB) }
        }
        .configurationDisplayName("Lights")
        .description("Lights that are on, plus your always-show favourites.")
        .supportedFamilies(WidgetPreviewKind.lights.widgetKitFamilies)
        .contentMarginsDisabled()
    }
}

// MARK: - Quick

struct QuickEntry: TimelineEntry { let date: Date; let snap: QuickSnapshot }

struct QuickProvider: TimelineProvider {
    func placeholder(in context: Context) -> QuickEntry { QuickEntry(date: .now, snap: .sample) }
    func getSnapshot(in context: Context, completion: @escaping (QuickEntry) -> Void) {
        if context.isPreview { completion(QuickEntry(date: .now, snap: .sample)); return }
        nonisolated(unsafe) let completion = completion
        Task { completion(QuickEntry(date: .now, snap: await Self.fetch())) }
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<QuickEntry>) -> Void) {
        nonisolated(unsafe) let completion = completion
        Task {
            let snap = await QuickProvider.fetch()
            completion(Timeline(entries: [QuickEntry(date: .now, snap: snap)],
                                policy: .after(Date().addingTimeInterval(60 * 60))))
        }
    }
    private static func fetch() async -> QuickSnapshot {
        #if DEBUG
        if ParityCatalog.activeWidgetID(prefix: "quick") != nil { return .loading }
        #endif
        return await fetchQuickSnapshot(HaConfigStore.load())
    }
}

struct QuickWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "com.rohit.hearth.quick", provider: QuickProvider()) { entry in
            ParityWidgetContent(prefix: "quick") { QuickView(entry.snap) }
                .containerBackground(for: .widget) { Color(argb: BeaconSurfaceColors.graphiteARGB) }
        }
        .configurationDisplayName("Quick")
        .description("Run your scripts and scenes.")
        .supportedFamilies(WidgetPreviewKind.quick.widgetKitFamilies)
        .contentMarginsDisabled()
    }
}

// MARK: - Favourites

struct FavouritesEntry: TimelineEntry { let date: Date; let snap: FavSnapshot }

struct FavouritesProvider: TimelineProvider {
    func placeholder(in context: Context) -> FavouritesEntry { FavouritesEntry(date: .now, snap: .sample) }
    func getSnapshot(in context: Context, completion: @escaping (FavouritesEntry) -> Void) {
        if context.isPreview { completion(FavouritesEntry(date: .now, snap: .sample)); return }
        nonisolated(unsafe) let completion = completion
        Task { completion(FavouritesEntry(date: .now, snap: await Self.fetch())) }
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<FavouritesEntry>) -> Void) {
        nonisolated(unsafe) let completion = completion
        Task {
            let snap = await FavouritesProvider.fetch()
            completion(Timeline(entries: [FavouritesEntry(date: .now, snap: snap)],
                                policy: .after(Date().addingTimeInterval(15 * 60))))
        }
    }
    private static func fetch() async -> FavSnapshot {
        #if DEBUG
        if ParityCatalog.activeWidgetID(prefix: "favourites") != nil { return .loading }
        #endif
        return await fetchFavouritesSnapshot(HaConfigStore.load())
    }
}

struct FavouritesWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "com.rohit.hearth.favourites", provider: FavouritesProvider()) { entry in
            ParityWidgetContent(prefix: "favourites") { FavouritesView(entry.snap) }
                .containerBackground(for: .widget) { Color(argb: BeaconSurfaceColors.graphiteARGB) }
        }
        .configurationDisplayName("Favourites")
        .description("Your pinned switches, lights, fans and scripts.")
        .supportedFamilies(WidgetPreviewKind.favourites.widgetKitFamilies)
        .contentMarginsDisabled()
    }
}

// MARK: - Doors

struct DoorsEntry: TimelineEntry { let date: Date; let snap: DoorsSnapshot }

struct DoorsProvider: TimelineProvider {
    func placeholder(in context: Context) -> DoorsEntry { DoorsEntry(date: .now, snap: .sample) }
    func getSnapshot(in context: Context, completion: @escaping (DoorsEntry) -> Void) {
        if context.isPreview { completion(DoorsEntry(date: .now, snap: .sample)); return }
        nonisolated(unsafe) let completion = completion
        Task { completion(DoorsEntry(date: .now, snap: await Self.fetch())) }
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<DoorsEntry>) -> Void) {
        nonisolated(unsafe) let completion = completion
        Task {
            let snap = await DoorsProvider.fetch()
            completion(Timeline(entries: [DoorsEntry(date: .now, snap: snap)],
                                policy: .after(Date().addingTimeInterval(10 * 60))))
        }
    }
    private static func fetch() async -> DoorsSnapshot {
        #if DEBUG
        if ParityCatalog.activeWidgetID(prefix: "doors") != nil { return .loading }
        #endif
        return await CollectionLiveSnapshots.doors()
    }
}

struct DoorsWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "com.rohit.hearth.doors", provider: DoorsProvider()) { entry in
            ParityWidgetContent(prefix: "doors") { DoorsView(entry.snap) }
                .containerBackground(for: .widget) { Color(argb: entry.snap.summary.tone.fillARGB) }
        }
        .configurationDisplayName("Doors")
        .description("Doors, garages and the front-door lock.")
        .supportedFamilies(WidgetPreviewKind.doors.widgetKitFamilies)
        .contentMarginsDisabled()
    }
}

// MARK: - Car

struct CarEntry: TimelineEntry {
    let payload: CarReadingsEntryPayload
    var date: Date { payload.date }
    var snap: CarSnapshot { payload.snapshot }
    #if DEBUG
    let interactionGeneration: UUID
    let probeIdentity: CarRouteProbeEntryIdentity?
    init(payload: CarReadingsEntryPayload,
         interactionGeneration: UUID = ParityCatalog.widgetInteractionGeneration(),
         probeIdentity: CarRouteProbeEntryIdentity? = nil) {
        self.payload = payload
        self.interactionGeneration = interactionGeneration
        self.probeIdentity = probeIdentity
    }
    #endif

    var allowsInteractions: Bool {
        guard payload.destination != .inert else { return false }
        #if DEBUG
        guard ParityCatalog.activeWidgetID(prefix: "car") == nil,
              interactionGeneration == ParityCatalog.widgetInteractionGeneration() else { return false }
        if let probeIdentity {
            guard CarRouteProbe.allowsPublication(run: probeIdentity.run) else { return false }
        }
        #endif
        return true
    }

    /// Strip stale route metadata as well as executable controls before constructing the card.
    var currentInteractionEntry: CarEntry {
        if allowsInteractions { return self }
        let inert = payload.disablingInteractions()
        #if DEBUG
        return CarEntry(payload: inert, interactionGeneration: interactionGeneration,
            probeIdentity: probeIdentity)
        #else
        return CarEntry(payload: inert)
        #endif
    }
}

struct CarProvider: TimelineProvider, Sendable {
    #if DEBUG
    let probeSlot: CarRouteProbeSlot?
    init(probeSlot: CarRouteProbeSlot? = nil) { self.probeSlot = probeSlot }
    #endif

    func placeholder(in context: Context) -> CarEntry {
        CarEntry(payload: CarReadingsEntryPayload(entryID: UUID(), date: .now, snapshot: .sample,
            destination: .inert, primary: .battery(72)))
    }
    func getSnapshot(in context: Context, completion: @escaping (CarEntry) -> Void) {
        let isPreview = context.isPreview
        nonisolated(unsafe) let completion = completion
        Task { completion(await loadEntry(isPreview: isPreview, callbackKind: "snapshot")) }
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<CarEntry>) -> Void) {
        let isPreview = context.isPreview
        // WidgetKit's completion predates Swift concurrency (not `@Sendable`) and is invoked exactly
        // once; `nonisolated(unsafe)` is the sanctioned bridge for carrying it into the async `Task`.
        nonisolated(unsafe) let completion = completion
        Task {
            let entry = await loadEntry(isPreview: isPreview, callbackKind: "timeline")
            completion(Timeline(entries: [entry],
                                policy: .after(Date().addingTimeInterval(15 * 60))))
        }
    }

    private func loadEntry(isPreview: Bool, callbackKind: String) async -> CarEntry {
        #if DEBUG
        let generation = ParityCatalog.widgetInteractionGeneration()
        let inert = isPreview || ParityCatalog.activeWidgetID(prefix: "car") != nil
        if let probeSlot {
            // Gallery, parity and invalid probe selections exit before opening any private store.
            guard !inert, case .armed(let run) = CarRouteProbe.selection(),
                  let probe = try? CarRouteProbe.dependencies(run: run, slot: probeSlot) else {
                return CarEntry(payload: CarReadingsEntryPayload(entryID: UUID(), date: .now,
                    snapshot: .sample, destination: .inert, primary: .battery(72)), interactionGeneration: generation)
            }
            let persisted = CarRouteProbePersistedTicket()
            let payload = await CarLiveSnapshot.loadEntry(selection: .live, probe: probe,
                didPersist: { persisted.capture($0) },
                allowsLivePublication: {
                    ParityCatalog.activeWidgetID(prefix: "car") == nil &&
                        ParityCatalog.widgetInteractionGeneration() == generation &&
                        CarRouteProbe.allowsPublication(run: run)
                })
            let entry = CarEntry(payload: payload, interactionGeneration: generation,
                probeIdentity: CarRouteProbeEntryIdentity(run: run, slot: probeSlot,
                    callbackKind: callbackKind)).currentInteractionEntry
            CarRouteProbeWidgetReceipts.providerCompleted(entry: entry, probe: probe,
                persistedTicket: persisted.value)
            return entry
        }
        let payload = await CarLiveSnapshot.loadEntry(selection: inert ? .inert : .live,
            allowsLivePublication: {
                ParityCatalog.activeWidgetID(prefix: "car") == nil &&
                    ParityCatalog.widgetInteractionGeneration() == generation
            })
        return CarEntry(payload: payload, interactionGeneration: generation)
        #else
        return CarEntry(payload: await CarLiveSnapshot.loadEntry(selection: isPreview ? .inert : .live))
        #endif
    }
}

private struct CarWidgetEntryView: View {
    let entry: CarEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        CarWidgetPresentation(payload: entry.payload, family: family)
    }
}

struct CarWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "com.rohit.hearth.car", provider: CarProvider()) { originalEntry in
            ParityWidgetContent(prefix: "car") {
                let entry = originalEntry.currentInteractionEntry
                CarWidgetEntryView(entry: entry)
            }
                .containerBackground(for: .widget) { Color(argb: BeaconSurfaceColors.graphiteARGB) }
        }
        .configurationDisplayName("Car")
        .description("Your car's battery, doors, and charge at a glance.")
        .supportedFamilies(WidgetPreviewKind.car.widgetKitFamilies)
        .contentMarginsDisabled()
    }
}

// MARK: - Alarm

struct AlarmEntry: TimelineEntry {
    let date: Date
    let snap: AlarmSnapshot
    let payload: AlarmReadingsEntryPayload?
    init(date: Date, snap: AlarmSnapshot) { self.date = date; self.snap = snap; payload = nil }
    init(payload: AlarmReadingsEntryPayload) { date = payload.date; snap = payload.snapshot; self.payload = payload }
}

struct AlarmProvider: TimelineProvider {
    func placeholder(in context: Context) -> AlarmEntry { AlarmEntry(date: .now, snap: .sample) }
    func getSnapshot(in context: Context, completion: @escaping (AlarmEntry) -> Void) {
        if context.isPreview { completion(AlarmEntry(date: .now, snap: .sample)); return }
        nonisolated(unsafe) let completion = completion
        Task { completion(await Self.fetch()) }
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<AlarmEntry>) -> Void) {
        nonisolated(unsafe) let completion = completion
        Task {
            let entry = await Self.fetch()
            completion(Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(15 * 60))))
        }
    }
    private static func fetch() async -> AlarmEntry {
        #if DEBUG
        if ParityCatalog.activeWidgetID(prefix: "alarm") != nil { return AlarmEntry(date: .now, snap: .sample) }
        #endif
        let snapshot = await AlarmLiveSnapshot.fetch()
        return AlarmEntry(payload: AlarmReadingsStore.bind(snapshot))
    }
}

struct AlarmWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "com.rohit.hearth.alarm", provider: AlarmProvider()) { entry in
            AlarmWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Home Alarm")
        .description("Your alarm state and front door at a glance.")
        .supportedFamilies(WidgetPreviewKind.alarm.widgetKitFamilies)
        .contentMarginsDisabled()
    }
}

private struct AlarmWidgetEntryView: View {
    let entry: AlarmEntry
    @Environment(\.widgetFamily) private var family
    var body: some View {
        ParityWidgetContent(prefix: "alarm") {
            if let payload = entry.payload { AlarmBeaconView(payload, family: family) }
            else { AlarmBeaconView(entry.snap, family: family) }
        }
        .widgetURL(family == .systemSmall ? alarmReadingsURL(for: entry.payload?.destination ?? .inert) : nil)
        .containerBackground(for: .widget) { Color(argb: BeaconSurfaceColors.graphiteARGB) }
    }
}

// MARK: - Thermostat

struct ThermostatEntry: TimelineEntry {
    let date: Date
    let snap: ThermostatSnapshot
    let payload: ThermostatEntryPayload?
    init(date: Date, snap: ThermostatSnapshot) { self.date = date; self.snap = snap; payload = nil }
    init(payload: ThermostatEntryPayload) { date = payload.date; snap = payload.snapshot; self.payload = payload }
}

struct ThermostatProvider: TimelineProvider {
    func placeholder(in context: Context) -> ThermostatEntry { ThermostatEntry(date: .now, snap: .sample) }
    func getSnapshot(in context: Context, completion: @escaping (ThermostatEntry) -> Void) {
        if context.isPreview { completion(ThermostatEntry(date: .now, snap: .sample)); return }
        nonisolated(unsafe) let completion = completion
        Task { completion(await Self.fetch()) }
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<ThermostatEntry>) -> Void) {
        nonisolated(unsafe) let completion = completion
        Task {
            let entry = await Self.fetch()
            completion(Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(15 * 60))))
        }
    }
    private static func fetch() async -> ThermostatEntry {
        #if DEBUG
        if ParityCatalog.activeWidgetID(prefix: "thermostat") != nil { return ThermostatEntry(date: .now, snap: .sample) }
        #endif
        let envelope = await ThermostatLiveSnapshot.fetchEnvelope()
        return ThermostatEntry(payload: ThermostatReadingsStore.bind(envelope))
    }
}

struct ThermostatWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "com.rohit.hearth.thermostat", provider: ThermostatProvider()) { entry in
            ThermostatWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Thermostat")
        .description("Your thermostat's temperature and setpoints at a glance.")
        .supportedFamilies(WidgetPreviewKind.thermostat.widgetKitFamilies)
        .contentMarginsDisabled()
    }
}

private struct ThermostatWidgetEntryView: View {
    let entry: ThermostatEntry
    @Environment(\.widgetFamily) private var family
    var body: some View {
        ParityWidgetContent(prefix: "thermostat") {
            if let payload = entry.payload { ThermostatBeaconView(payload, family: family) }
            else { ThermostatBeaconView(entry.snap, family: family) }
        }
        .widgetURL(navigationURL)
        .containerBackground(for: .widget) { Color(argb: BeaconSurfaceColors.graphiteARGB) }
    }
    private var navigationURL: URL? {
        guard let payload = entry.payload else { return nil }
        return family == .systemSmall
            ? thermostatSmallContent(payload.presentation, destination: payload.destination).navigationURL
            : thermostatReadingsURL(for: payload.destination)
    }
}

// MARK: - ChargePoint

struct CpEntry: TimelineEntry {
    let date: Date
    let snap: CpSnapshot
}

struct CpProvider: TimelineProvider {
    func placeholder(in context: Context) -> CpEntry { CpEntry(date: .now, snap: .sample) }
    func getSnapshot(in context: Context, completion: @escaping (CpEntry) -> Void) {
        if context.isPreview { completion(CpEntry(date: .now, snap: .sample)); return }
        nonisolated(unsafe) let completion = completion
        Task {
            completion(CpEntry(date: .now, snap: await CpProvider.fetch(advanceAuto: false)))
        }
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<CpEntry>) -> Void) {
        nonisolated(unsafe) let completion = completion
        Task {
            let displays = await CpProvider.fetchTimeline()
            let entries = displays.map { CpEntry(date: $0.date, snap: $0.snapshot) }
            let capturedAt = displays[0].date
            completion(Timeline(entries: entries,
                                policy: .after(capturedAt.addingTimeInterval(15 * 60))))
        }
    }

    private static func fetchTimeline() async -> [CpTimelineDisplay] {
        #if DEBUG
        if ParityCatalog.activeWidgetID(prefix: "chargepoint") != nil {
            return [CpTimelineDisplay(date: .now, snapshot: .sample)]
        }
        #endif
        return await CpLiveSnapshot.fetchTimeline()
    }

    private static func fetch(advanceAuto: Bool = true) async -> CpSnapshot {
        #if DEBUG
        if ParityCatalog.activeWidgetID(prefix: "chargepoint") != nil { return .sample }
        #endif
        // iOS schedules refreshes at its discretion; Auto remains best-effort.
        return await CpLiveSnapshot.fetch(advanceAuto: advanceAuto)
    }
}

struct ChargePointWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "com.rohit.hearth.chargepoint", provider: CpProvider()) { entry in
            ParityWidgetContent(prefix: "chargepoint") { CpBeaconView(entry.snap) }
                .containerBackground(for: .widget) { Color(argb: BeaconSurfaceColors.graphiteARGB) }
        }
        .configurationDisplayName("ChargePoint")
        .description("Your ChargePoint site, waitlist, and charging at a glance.")
        .supportedFamilies(WidgetPreviewKind.chargepoint.widgetKitFamilies)
        .contentMarginsDisabled()
    }
}
