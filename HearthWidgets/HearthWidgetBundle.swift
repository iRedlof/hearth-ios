import WidgetKit
import SwiftUI
import HearthKit

@main
struct HearthWidgetBundle: WidgetBundle {
    var body: some Widget { CarWidget() }
}

struct CarEntry: TimelineEntry {
    let date: Date
    let snap: CarSnapshot
}

/// For now the provider serves sample data so the widget renders; wiring it to `HaClient` (fetch via
/// POST /api/template, App-Group config) is the next step once the HearthKit client lands.
struct CarProvider: TimelineProvider {
    func placeholder(in context: Context) -> CarEntry { CarEntry(date: .now, snap: .sample) }

    func getSnapshot(in context: Context, completion: @escaping (CarEntry) -> Void) {
        completion(CarEntry(date: .now, snap: .sample))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<CarEntry>) -> Void) {
        let entry = CarEntry(date: .now, snap: .sample)
        completion(Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(15 * 60))))
    }
}

struct CarWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "com.rohit.hearth.car", provider: CarProvider()) { entry in
            CarBeaconView(entry.snap)
                .containerBackground(for: .widget) {
                    Color(argb: BeaconSurfaceColors.graphiteARGB)
                }
        }
        .configurationDisplayName("Car")
        .description("Your car's battery, doors, and charge at a glance.")
        .supportedFamilies([.systemMedium])
        .contentMarginsDisabled()
    }
}
