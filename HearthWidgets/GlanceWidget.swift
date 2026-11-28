import WidgetKit
import SwiftUI
import HearthKit

// MARK: - Glance Widget

struct GlanceEntry: TimelineEntry {
    let date: Date
    let summary: GlanceSummary
}

struct GlanceProvider: TimelineProvider {
    func placeholder(in context: Context) -> GlanceEntry {
        GlanceEntry(date: .now, summary: placeholderSummary())
    }

    func getSnapshot(in context: Context, completion: @escaping (GlanceEntry) -> Void) {
        if context.isPreview {
            completion(GlanceEntry(date: .now, summary: placeholderSummary()))
            return
        }
        nonisolated(unsafe) let completion = completion
        Task {
            let summary = fetchGlanceSummary()
            completion(GlanceEntry(date: .now, summary: summary))
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<GlanceEntry>) -> Void) {
        nonisolated(unsafe) let completion = completion
        Task {
            let summary = fetchGlanceSummary()
            let entry = GlanceEntry(date: .now, summary: summary)
            completion(Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(15 * 60))))
        }
    }

    private func fetchGlanceSummary() -> GlanceSummary {
        #if DEBUG
        if ParityCatalog.activeWidgetID(prefix: "glance") != nil {
            return placeholderSummary()
        }
        #endif

        let feeds = GlanceFeedStore.load()
        return glanceSummary(feeds, now: .now)
    }

    private func placeholderSummary() -> GlanceSummary {
        GlanceSummary(
            verdict: .ok,
            word: "OK",
            tone: .ok,
            lines: [],
            support: "Checked 9:41",
            calmLine: "Alarm · Doors · Lights",
            key: nil
        )
    }
}

struct GlanceWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "com.rohit.hearth.glance", provider: GlanceProvider()) { entry in
            GlanceWidgetContainer(entry: entry)
        }
        .configurationDisplayName("Glance")
        .description("Shows only what needs you")
        .supportedFamilies([.systemSmall])
        .contentMarginsDisabled()
    }
}

private struct GlanceWidgetContainer: View {
    let entry: GlanceEntry
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        CardStyledContent(kind: .glance, statusARGB: entry.summary.tone.bgARGB(colorScheme)) {
            ParityWidgetContent(prefix: "glance") {
                GlanceWidgetEntryView(entry: entry)
            }
        }
    }
}

private struct GlanceWidgetEntryView: View {
    let entry: GlanceEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        let size: GlanceSize = family == .systemSmall ? .small2x1 : .small2x2
        let plan = glanceLayout(summary: entry.summary, size: size)
        GlanceView(summary: entry.summary, plan: plan)
    }
}
