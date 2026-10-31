#if DEBUG
import Foundation
import SwiftUI
import WidgetKit
import HearthKit

/// A retained entry keeps its original run and callback identity across redraws.
struct CarRouteProbeEntryIdentity: Sendable {
    let run: CarRouteProbeRun
    let slot: CarRouteProbeSlot
    let callbackKind: String
}

/// Captures only the immutable ticket accepted by this callback's real persistence boundary.
/// Diagnostic capture neither issues a record nor borrows one from the current HA cache.
final class CarRouteProbePersistedTicket: @unchecked Sendable {
    private let lock = NSLock()
    private var ticket: CarReadingsTicket?

    func capture(_ ticket: CarReadingsTicket) {
        lock.lock(); defer { lock.unlock() }
        self.ticket = ticket
    }

    var value: CarReadingsTicket? {
        lock.lock(); defer { lock.unlock() }
        return ticket
    }
}

enum CarRouteProbeWidgetReceipts {
    static func destination(_ destination: CarReadingsDestination) -> String {
        switch destination {
        case .ticket: "ticket"
        case .storageUnavailable: "storageUnavailable"
        case .inert: "inert"
        }
    }

    private static func fields(_ entry: CarEntry) -> [String: String] {
        var fields = [
            "callbackKind": entry.probeIdentity?.callbackKind ?? "inert",
            "entryID": entry.payload.entryID.uuidString,
            "destination": destination(entry.payload.destination),
            "snapshotName": entry.snap.name,
            "snapshotBattery": entry.snap.battery.map(String.init) ?? "unavailable"
        ]
        if case .ticket(let ticketID) = entry.payload.destination {
            fields["ticketID"] = ticketID.uuidString
        }
        return fields
    }

    static func providerCompleted(entry: CarEntry, probe: CarRouteProbeDependencies,
                                  persistedTicket: CarReadingsTicket?) {
        var fields = fields(entry)
        let counts = probe.counts
        fields["privateStoreID"] = "Runs/\(probe.run.runID.uuidString)/Tickets"
        fields["fetchCount"] = String(counts.fetch)
        fields["saveCount"] = String(counts.save)
        fields["transportCount"] = String(counts.transport)
        fields["issuedAt"] = String(entry.date.timeIntervalSince1970)
        if case .ticket(let ticketID) = entry.payload.destination,
           let ticket = persistedTicket, ticket.id == ticketID,
           ticket.entryID == entry.payload.entryID {
            fields["issuedAt"] = String(ticket.issuedAt.timeIntervalSince1970)
            fields["expiresAt"] = String(ticket.expiresAt.timeIntervalSince1970)
            fields["ticketDigest"] = try? CarRouteProbeReceiptWriter.ticketDigest(ticket)
            fields["attemptedAt"] = String(ticket.origin.attemptedAt.timeIntervalSince1970)
            fields["observedAt"] = ticket.origin.observedAt.map { String($0.timeIntervalSince1970) }
            fields["displayedObservedAt"] = ticket.origin.displayedObservedAt.map {
                String($0.timeIntervalSince1970)
            }
        }
        probe.receipts.record(phase: "providerCompleted", fields: fields)
    }

    /// A bounded diagnostic event for this actual body evaluation; it never opens HA/ticket stores.
    /// Repeated provider callbacks and redraws each receive a fresh event UUID.
    static func widgetRendered(entry: CarEntry) {
        guard let identity = entry.probeIdentity,
              let receipts = try? CarRouteProbe.receipts(run: identity.run, slot: identity.slot) else { return }
        receipts.record(phase: "widgetRendered", fields: fields(entry))
    }
}

struct CarReadingsRouteProbeWidget: Widget {
    let slot: CarRouteProbeSlot

    init() { slot = .a }
    init(slot: CarRouteProbeSlot) { self.slot = slot }

    private var kind: String {
        slot == .a ? "com.rohit.hearth.car-readings-probe-a" : "com.rohit.hearth.car-readings-probe-b"
    }

    private var displayName: LocalizedStringKey {
        slot == .a ? "DEBUG Car route A" : "DEBUG Car route B"
    }

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: CarProvider(probeSlot: slot)) { entry in
            ParityWidgetContent(prefix: "car") {
                CarReadingsRouteProbeView(entry: entry, slot: slot)
            }
            .containerBackground(for: .widget) { Color(argb: BeaconSurfaceColors.graphiteARGB) }
        }
        .configurationDisplayName(displayName)
        .description("Opens this controlled widget entry's saved reading.")
        .supportedFamilies([.systemMedium])
        .contentMarginsDisabled()
    }
}

private struct CarReadingsRouteProbeView: View {
    let entry: CarEntry
    let slot: CarRouteProbeSlot

    var body: some View {
        let currentEntry = entry.currentInteractionEntry
        let _ = CarRouteProbeWidgetReceipts.widgetRendered(entry: currentEntry)
        content(currentEntry)
            .widgetURL(carReadingsURL(for: currentEntry.payload.destination))
    }

    private func content(_ entry: CarEntry) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline) {
                Text("DEBUG Car route \(slot.rawValue)")
                    .font(.system(size: 15, weight: .bold))
                Spacer(minLength: 4)
                Text(entry.snap.battery.map { "\($0)%" } ?? "—")
                    .font(.system(size: 24, weight: .heavy))
            }
            Text(entry.snap.name)
                .font(.system(size: 13, weight: .medium))
                .lineLimit(2)
            Text("Run \(short(entry.probeIdentity?.run.runID)) · Build \(build(entry))")
                .font(.system(size: 10, design: .monospaced))
                .lineLimit(1)
            Text("Entry \(short(entry.payload.entryID)) · Ticket \(ticket(entry))")
                .font(.system(size: 10, design: .monospaced))
                .lineLimit(1)
            Spacer(minLength: 0)
            Text(actionTitle(entry.payload.destination))
                .font(.system(size: 13, weight: .semibold))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 7)
                .padding(.horizontal, 9)
                .background(.white.opacity(0.11), in: RoundedRectangle(cornerRadius: 8))
        }
        .foregroundStyle(Color(argb: BeaconSurfaceColors.inkARGB))
        .padding(12)
        .accessibilityIdentifier("car-route-probe-\(slot.rawValue)")
    }

    private func short(_ id: UUID?) -> String {
        id.map { String($0.uuidString.prefix(8)) } ?? "—"
    }

    private func build(_ entry: CarEntry) -> String {
        String((entry.probeIdentity?.run.buildMarker ?? CarRouteProbeBuild.marker).suffix(12))
    }

    private func ticket(_ entry: CarEntry) -> String {
        switch entry.payload.destination {
        case .ticket(let id): short(id)
        case .storageUnavailable: "unavailable"
        case .inert: "none"
        }
    }

    private func actionTitle(_ destination: CarReadingsDestination) -> String {
        switch destination {
        case .ticket: "Open this saved reading"
        case .storageUnavailable: "Open save-failure explanation"
        case .inert: "Inactive — no saved route"
        }
    }
}
#endif
