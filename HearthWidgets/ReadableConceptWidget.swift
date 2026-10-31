#if DEBUG
import SwiftUI
import WidgetKit

/// A dedicated inert WidgetKit host for comparing all four summaries at the same real Medium size.
struct ReadableConceptWidget: Widget {
    private struct Entry: TimelineEntry { let date: Date }
    private struct Provider: TimelineProvider {
        func placeholder(in context: Context) -> Entry { .init(date: .now) }
        func getSnapshot(in context: Context, completion: @escaping (Entry) -> Void) { completion(.init(date: .now)) }
        func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> Void) {
            completion(.init(entries: [.init(date: .now)], policy: .never))
        }
    }
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "com.rohit.hearth.readable", provider: Provider()) { _ in
            ParityWidgetContent(prefix: "readable") {
                AccessibleBeaconConceptView(concept: AccessibleBeaconConceptCatalog.concepts[0])
                    .allowsHitTesting(false)
            }
            .containerBackground(for: .widget) { Color(red: 0.12, green: 0.15, blue: 0.13) }
        }
        .configurationDisplayName("Larger-text concepts")
        .description("Inert design prototypes with example readings.")
        .supportedFamilies([.systemMedium])
        .contentMarginsDisabled()
    }
}
#endif
