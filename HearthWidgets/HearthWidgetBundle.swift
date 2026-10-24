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
