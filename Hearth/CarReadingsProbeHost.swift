#if DEBUG
import SwiftUI
import HearthKit

/// Captures a validated run and builds the real receiving scene immediately, without auto-opening.
struct CarReadingsProbeHost: View {
    let run: CarRouteProbeRun
    private let content: ContentView?
    private let receipts: CarRouteProbeReceiptWriter?
    private let failure: String?
    private let selectorConflict: String?

    init(run: CarRouteProbeRun) {
        self.run = run
        selectorConflict = CarRouteProbe.selectorConflict(arguments: ProcessInfo.processInfo.arguments)
        do {
            let dependencies = try CarRouteProbe.dependencies(run: run, slot: .a)
            let writer = try CarRouteProbe.receipts(run: run)
            receipts = writer
            let runtime = CarReadingsRuntime(tickets: dependencies.tickets, state: dependencies.state,
                request: dependencies.request, reloadWidget: {
                    writer.record(phase: "widgetRefreshRequested", fields: ["controlledResult": "inertReload"])
                    return "DEBUG controlled run: widget refresh was recorded. Use the probe harness to reload its widgets."
                }, probeReceipts: writer)
            content = ContentView(carReadingsRuntime: runtime, inertTabs: true)
            failure = nil
        } catch {
            content = nil; receipts = nil
            failure = "The captured DEBUG run's private stores cannot be opened. Arm a new controlled run."
            CarRouteProbe.recordBlocked(reason: "capturedPrivateStoresUnavailable", run: run)
        }
    }

    var body: some View {
        Group {
            if let content {
                content
                    .safeAreaInset(edge: .top) {
                        VStack(spacing: 3) {
                            Text("DEBUG Car route probe · controlled data").font(.caption.bold())
                            Text("Run \(run.runID.uuidString.prefix(8)) · \(run.scenario.rawValue)").font(.caption2)
                            Text(run.buildMarker).font(.caption2)
                            if let selectorConflict { Text(selectorConflict).font(.caption2) }
                        }.frame(maxWidth: .infinity).padding(.vertical, 5).background(.regularMaterial)
                    }
                    .environment(\.openURL, OpenURLAction { url in
                        if url.scheme?.lowercased() == "tesla" {
                            receipts?.record(phase: "teslaDiscarded", fields: ["controlledResult": "discarded"])
                        }
                        return .discarded
                    })
            } else {
                CarReadingsProbeBlockedHost(reason: failure ?? "The controlled DEBUG run is unavailable.")
            }
        }
    }
}

/// This host has no runtime, config, dashboard, sign-in, settings or auth object.
struct CarReadingsProbeBlockedHost: View {
    let reason: String
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("DEBUG Car route probe · blocked").font(.headline)
            Text(reason).fixedSize(horizontal: false, vertical: true)
            Text("Controlled isolation remains active. No saved Car reading can be opened from this run.")
                .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }.padding().frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
#endif
