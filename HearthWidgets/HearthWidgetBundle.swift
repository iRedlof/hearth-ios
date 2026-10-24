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
    }
}

// MARK: - Batteries

struct BatteryEntry: TimelineEntry { let date: Date; let snap: BatterySnapshot }

struct BatteryProvider: TimelineProvider {
    func placeholder(in context: Context) -> BatteryEntry { BatteryEntry(date: .now, snap: .sample) }
    func getSnapshot(in context: Context, completion: @escaping (BatteryEntry) -> Void) {
        completion(BatteryEntry(date: .now, snap: .sample))
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
        guard let cfg = HaConfigStore.load(), cfg.baseUrl.hasPrefix("https://"), cfg.hasAuth else { return .sample }
        return await fetchBatterySnapshot(cfg)
    }
}

struct BatteryWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "com.rohit.hearth.battery", provider: BatteryProvider()) { entry in
            BatteryView(entry.snap)
                .containerBackground(for: .widget) { Color(argb: entry.snap.summary.tone.fillARGB) }
        }
        .configurationDisplayName("Batteries")
        .description("Every battery you replace, lowest first.")
        .supportedFamilies([.systemLarge, .systemMedium])
        .contentMarginsDisabled()
    }
}

// MARK: - Activity

struct ActivityEntry: TimelineEntry { let date: Date; let snap: ActivitySnapshot }

struct ActivityProvider: TimelineProvider {
    func placeholder(in context: Context) -> ActivityEntry { ActivityEntry(date: .now, snap: .sample) }
    func getSnapshot(in context: Context, completion: @escaping (ActivityEntry) -> Void) {
        completion(ActivityEntry(date: .now, snap: .sample))
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
        guard let cfg = HaConfigStore.load() else { return .sample }
        return await fetchActivitySnapshot(cfg)
    }
}

struct ActivityWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "com.rohit.hearth.activity", provider: ActivityProvider()) { entry in
            ActivityView(entry.snap)
                .containerBackground(for: .widget) { Color(argb: DoorsTone.unknown.fillARGB) }
        }
        .configurationDisplayName("Activity")
        .description("Recent home events — doors, locks, alarm.")
        .supportedFamilies([.systemLarge])
        .contentMarginsDisabled()
    }
}

// MARK: - Lights

struct LightsEntry: TimelineEntry { let date: Date; let snap: LightsSnapshot }

struct LightsProvider: TimelineProvider {
    func placeholder(in context: Context) -> LightsEntry { LightsEntry(date: .now, snap: .sample) }
    func getSnapshot(in context: Context, completion: @escaping (LightsEntry) -> Void) {
        completion(LightsEntry(date: .now, snap: .sample))
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
        guard let cfg = HaConfigStore.load(), cfg.baseUrl.hasPrefix("https://"), cfg.hasAuth else { return .sample }
        return await fetchLightsSnapshot(cfg)
    }
}

struct LightsWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "com.rohit.hearth.lights", provider: LightsProvider()) { entry in
            LightTileView(entry.snap)
                .containerBackground(for: .widget) { Color(argb: BeaconSurfaceColors.graphiteARGB) }
        }
        .configurationDisplayName("Lights")
        .description("Lights that are on, plus your always-show favourites.")
        .supportedFamilies([.systemLarge])
        .contentMarginsDisabled()
    }
}

// MARK: - Quick

struct QuickEntry: TimelineEntry { let date: Date; let snap: QuickSnapshot }

struct QuickProvider: TimelineProvider {
    func placeholder(in context: Context) -> QuickEntry { QuickEntry(date: .now, snap: .sample) }
    func getSnapshot(in context: Context, completion: @escaping (QuickEntry) -> Void) {
        completion(QuickEntry(date: .now, snap: .sample))
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
        guard let cfg = HaConfigStore.load(), cfg.baseUrl.hasPrefix("https://"), cfg.hasAuth else { return .sample }
        return await fetchQuickSnapshot(cfg)
    }
}

struct QuickWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "com.rohit.hearth.quick", provider: QuickProvider()) { entry in
            QuickView(entry.snap)
                .containerBackground(for: .widget) { Color(argb: BeaconSurfaceColors.graphiteARGB) }
        }
        .configurationDisplayName("Quick")
        .description("Run your scripts and scenes.")
        .supportedFamilies([.systemMedium])
        .contentMarginsDisabled()
    }
}

// MARK: - Favourites

struct FavouritesEntry: TimelineEntry { let date: Date; let snap: FavSnapshot }

struct FavouritesProvider: TimelineProvider {
    func placeholder(in context: Context) -> FavouritesEntry { FavouritesEntry(date: .now, snap: .sample) }
    func getSnapshot(in context: Context, completion: @escaping (FavouritesEntry) -> Void) {
        completion(FavouritesEntry(date: .now, snap: .sample))
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
        guard let cfg = HaConfigStore.load(), cfg.baseUrl.hasPrefix("https://"), cfg.hasAuth else { return .sample }
        return await fetchFavouritesSnapshot(cfg)
    }
}

struct FavouritesWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "com.rohit.hearth.favourites", provider: FavouritesProvider()) { entry in
            FavouritesView(entry.snap)
                .containerBackground(for: .widget) { Color(argb: BeaconSurfaceColors.graphiteARGB) }
        }
        .configurationDisplayName("Favourites")
        .description("Your pinned switches, lights, fans and scripts.")
        .supportedFamilies([.systemLarge])
        .contentMarginsDisabled()
    }
}

// MARK: - Car

struct CarEntry: TimelineEntry {
    let date: Date
    let snap: CarSnapshot
}

struct CarProvider: TimelineProvider {
    func placeholder(in context: Context) -> CarEntry { CarEntry(date: .now, snap: .sample) }
    func getSnapshot(in context: Context, completion: @escaping (CarEntry) -> Void) {
        completion(CarEntry(date: .now, snap: .sample))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<CarEntry>) -> Void) {
        // WidgetKit's completion predates Swift concurrency (not `@Sendable`) and is invoked exactly
        // once; `nonisolated(unsafe)` is the sanctioned bridge for carrying it into the async `Task`.
        nonisolated(unsafe) let completion = completion
        Task {
            let snap = await CarProvider.fetch()
            completion(Timeline(entries: [CarEntry(date: .now, snap: snap)],
                                policy: .after(Date().addingTimeInterval(15 * 60))))
        }
    }

    /// Reads the App-Group `HaConfig`; when signed in, renders the car via `POST /api/template`.
    /// Not signed in → `.sample` (shows a representative preview). A fetch error also falls back to
    /// `.sample` for now. TODO: surface a real offline/error state on the widget face.
    private static func fetch() async -> CarSnapshot {
        guard let cfg = HaConfigStore.load(), cfg.carReady else { return .sample }
        do {
            let json = try await HaClient(cfg).template(CAR_TEMPLATE)
            let now = Date()
            return carSnapshot(carFromTemplate(json), now: now, stale: false, checkedAt: now)
        } catch {
            return .sample
        }
    }
}

struct CarWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "com.rohit.hearth.car", provider: CarProvider()) { entry in
            CarBeaconView(entry.snap)
                .containerBackground(for: .widget) { Color(argb: BeaconSurfaceColors.graphiteARGB) }
        }
        .configurationDisplayName("Car")
        .description("Your car's battery, doors, and charge at a glance.")
        .supportedFamilies([.systemMedium])
        .contentMarginsDisabled()
    }
}

// MARK: - Alarm

struct AlarmEntry: TimelineEntry {
    let date: Date
    let snap: AlarmSnapshot
}

struct AlarmProvider: TimelineProvider {
    func placeholder(in context: Context) -> AlarmEntry { AlarmEntry(date: .now, snap: .sample) }
    func getSnapshot(in context: Context, completion: @escaping (AlarmEntry) -> Void) {
        completion(AlarmEntry(date: .now, snap: .sample))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<AlarmEntry>) -> Void) {
        nonisolated(unsafe) let completion = completion
        Task {
            let snap = await AlarmProvider.fetch()
            completion(Timeline(entries: [AlarmEntry(date: .now, snap: snap)],
                                policy: .after(Date().addingTimeInterval(15 * 60))))
        }
    }

    /// Live alarm + door when configured; `.sample` otherwise (an error also falls back to sample).
    private static func fetch() async -> AlarmSnapshot {
        guard let cfg = HaConfigStore.load(), cfg.isComplete else { return .sample }
        return await fetchAlarmSnapshot(cfg)
    }
}

struct AlarmWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "com.rohit.hearth.alarm", provider: AlarmProvider()) { entry in
            AlarmBeaconView(entry.snap)
                .containerBackground(for: .widget) { Color(argb: BeaconSurfaceColors.graphiteARGB) }
        }
        .configurationDisplayName("Home Alarm")
        .description("Your alarm state and front door at a glance.")
        .supportedFamilies([.systemMedium])
        .contentMarginsDisabled()
    }
}

// MARK: - Thermostat

struct ThermostatEntry: TimelineEntry {
    let date: Date
    let snap: ThermostatSnapshot
}

struct ThermostatProvider: TimelineProvider {
    func placeholder(in context: Context) -> ThermostatEntry { ThermostatEntry(date: .now, snap: .sample) }
    func getSnapshot(in context: Context, completion: @escaping (ThermostatEntry) -> Void) {
        completion(ThermostatEntry(date: .now, snap: .sample))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<ThermostatEntry>) -> Void) {
        nonisolated(unsafe) let completion = completion
        Task {
            let snap = await ThermostatProvider.fetch()
            completion(Timeline(entries: [ThermostatEntry(date: .now, snap: snap)],
                                policy: .after(Date().addingTimeInterval(15 * 60))))
        }
    }

    private static func fetch() async -> ThermostatSnapshot {
        guard let cfg = HaConfigStore.load(), cfg.hasClimate else { return .sample }
        return await fetchThermostatSnapshot(cfg)
    }
}

struct ThermostatWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "com.rohit.hearth.thermostat", provider: ThermostatProvider()) { entry in
            ThermostatBeaconView(entry.snap)
                .containerBackground(for: .widget) { Color(argb: BeaconSurfaceColors.graphiteARGB) }
        }
        .configurationDisplayName("Thermostat")
        .description("Your thermostat's temperature and setpoints at a glance.")
        .supportedFamilies([.systemMedium])
        .contentMarginsDisabled()
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
        completion(CpEntry(date: .now, snap: .sample))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<CpEntry>) -> Void) {
        nonisolated(unsafe) let completion = completion
        Task {
            let snap = await CpProvider.fetch()
            completion(Timeline(entries: [CpEntry(date: .now, snap: snap)],
                                policy: .after(Date().addingTimeInterval(15 * 60))))
        }
    }

    private static func fetch() async -> CpSnapshot {
        let session = CpSessionStore.load()
        guard !session.token.isEmpty else { return .sample }   // never signed in → representative preview
        var run = CpSessionStore.loadRun()
        // Best-effort auto-waitlist: advance the tested engine on this refresh. iOS has no guaranteed
        // background cadence or exact pre-deadline wake (docs/CHARGEPOINT-IOS.md), so this runs when
        // the widget/app happens to refresh.
        if run.armed {
            let client = CpClient(token: session.token, userId: session.userId,
                                  onToken: { CpSessionStore.saveToken($0) })
            if let statusJson = try? await client.userStatus() {
                let result = await cpAdvanceAuto(run, client: client, statusJson: statusJson,
                                                 now: Int64(Date().timeIntervalSince1970 * 1000))
                run = result.run
                CpSessionStore.saveRun(run)
                if result.alert == .driveNow { CpNotify.driveNow() }
            }
        }
        return await fetchCpSnapshot(session, onToken: { CpSessionStore.saveToken($0) }, autoOn: run.armed)
    }
}

struct ChargePointWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "com.rohit.hearth.chargepoint", provider: CpProvider()) { entry in
            CpBeaconView(entry.snap)
                .containerBackground(for: .widget) { Color(argb: BeaconSurfaceColors.graphiteARGB) }
        }
        .configurationDisplayName("ChargePoint")
        .description("Your ChargePoint site, waitlist, and charging at a glance.")
        .supportedFamilies([.systemMedium])
        .contentMarginsDisabled()
    }
}
