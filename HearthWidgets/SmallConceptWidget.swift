#if DEBUG
import SwiftUI
import WidgetKit
import HearthKit

/// A pure, non-live WidgetKit host for reviewing the requested Small design spike.
private struct SmallConceptEntry: TimelineEntry { let date: Date }
private struct SmallConceptProvider: TimelineProvider {
    func placeholder(in context: Context) -> SmallConceptEntry { SmallConceptEntry(date: .now) }
    func getSnapshot(in context: Context, completion: @escaping (SmallConceptEntry) -> Void) {
        completion(SmallConceptEntry(date: .now))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<SmallConceptEntry>) -> Void) {
        completion(Timeline(entries: [SmallConceptEntry(date: .now)], policy: .never))
    }
}

struct SmallConceptWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "com.rohit.hearth.small", provider: SmallConceptProvider()) { _ in
            SmallMeasuredContent()
            .containerBackground(for: .widget) { Color(argb: BeaconSurfaceColors.graphiteARGB) }
        }
        .configurationDisplayName("Small design mocks")
        .description("Review a focused square layout with example data.")
        .supportedFamilies([.systemSmall])
        .contentMarginsDisabled()
    }
}

private struct SmallMeasuredContent: View {
    @Environment(\.widgetFamily) private var family
    @Environment(\.widgetContentMargins) private var margins

    var body: some View {
        GeometryReader { geometry in
            let _ = record(geometry.size)
            ParityWidgetContent(prefix: "small") {
                SmallWidgetConceptView(concept: SmallWidgetConceptCatalog.concepts[0])
            }
        }
    }

    private func record(_ size: CGSize) {
        let store = UserDefaults(suiteName: HaConfigStore.appGroup)
        store?.set([
            "width": size.width, "height": size.height,
            "family": String(describing: family),
            "systemContentMargins": ["top": margins.top, "leading": margins.leading,
                                     "bottom": margins.bottom, "trailing": margins.trailing],
            "customPadding": 11, "timestamp": Date().timeIntervalSince1970
        ], forKey: "smallConceptHost")
        store?.synchronize()
    }
}
#endif
