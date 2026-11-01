import SwiftUI
import HearthKit

/// Opening a Small Alarm is local and read-only: no fetch, refresh or physical service dependency.
struct AlarmReadingsScreen: View {
    let destination: AlarmReadingsDestination
    let inert: Bool
    let onSettings: () -> Void
    let onReconnect: () -> Void
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dismiss) private var dismiss
    @State private var ticket: AlarmReadingsTicket?
    @State private var status: AlarmReadingsStatus?
    @State private var explanation: String?
    private var snapshot: AlarmSnapshot? { ticket?.snapshot }

    var body: some View {
        NavigationStack {
            Form {
                if let explanation {
                    Section("Saved alarm readings") { Text(explanation).fixedSize(horizontal: false, vertical: true) }
                }
                if let snapshot {
                    if let status, status != .current {
                        Section("Reading needs attention") {
                            Text(recovery(status)).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    Section("Widget's saved panel reading") {
                        Text(snapshot.name).font(.headline).fixedSize(horizontal: false, vertical: true)
                        Text(alarmSmallContent(snapshot).criticalTexts.joined(separator: " · "))
                            .font(.title2.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
                        LabeledContent("Reported state", value: snapshot.panelRawState ?? "No reading")
                        if let error = snapshot.error { Text(error).fixedSize(horizontal: false, vertical: true) }
                        observation("Panel observed", snapshot.panelObservedAt)
                        observation("Panel state changed", snapshot.panelChangedAt)
                    }
                    Section("Widget's saved door reading") {
                        if snapshot.doorSelected {
                            Text(snapshot.doorName).font(.headline).fixedSize(horizontal: false, vertical: true)
                            LabeledContent(snapshot.doorStale ? "Last reported state" : "Reported state", value: snapshot.doorRawState ?? "No reading")
                            if let error = snapshot.doorError { Text(error).fixedSize(horizontal: false, vertical: true) }
                            observation("Door observed", snapshot.doorObservedAt)
                            observation("Door state changed", snapshot.doorChangedAt)
                        } else { Text("No door selected") }
                    }
                    if let operation = snapshot.operation {
                        Section("Saved operation feedback") {
                            LabeledContent("Action", value: operation.action)
                            LabeledContent("Entity", value: operation.entityID)
                            Text(snapshot.commandFeedback ?? "Updating").fixedSize(horizontal: false, vertical: true)
                            if let error = operation.error { Text(error).fixedSize(horizontal: false, vertical: true) }
                            observation("Started", operation.startedAt)
                        }
                    }
                }
                Section {
                    Text("These are the readings shown by the widget when this saved entry was created. Opening this screen does not arm, disarm, lock or unlock anything.")
                        .font(.body).fixedSize(horizontal: false, vertical: true)
                    if snapshot?.needsSignIn == true { Button("Reconnect Home Assistant", action: onReconnect).frame(minHeight: 44) }
                    if explanation != nil || status != .current || snapshot?.needsSettings == true {
                        Button("Open Settings", action: onSettings).frame(minHeight: 44)
                    }
                }
            }
            .navigationTitle("Alarm readings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }.frame(minHeight: 44)
            } }
            .task { open() }
            .onChange(of: scenePhase) { if scenePhase == .active { revalidate() } }
        }
    }
    @ViewBuilder private func observation(_ title: String, _ date: Date?) -> some View {
        if let date { LabeledContent(title, value: date.formatted(date: .abbreviated, time: .standard)) }
    }
    private func recovery(_ status: AlarmReadingsStatus) -> String {
        switch status {
        case .current: ""
        case .originChanged: "This saved alarm entry no longer matches the current alarm context. The account, selected panel or door, or operation may have changed. This saved reading has not been replaced with a newer or different home's reading. Open Settings to check the current selection."
        case .expired: "This saved widget reading has expired. Open Hearth's Live tab to obtain a new reading."
        case .storageUnavailable: "The current settings could not be read, so this saved entry cannot be verified. Reopen Hearth to try again."
        }
    }
    private func open() {
        guard ticket == nil, explanation == nil else { revalidate(); return }
        guard !inert, case .ticket(let id) = destination else {
            explanation = "This displayed alarm reading was not saved. It cannot be opened as an exact saved reading. Open Hearth's Live tab and check the current alarm there."; return
        }
        do {
            guard let store = AlarmReadingsStore.store else { throw HaError("Shared storage is unavailable") }
            switch try store.lookup(id) {
            case .available(let value): ticket = value; revalidate()
            case .expired: explanation = "This saved widget reading has expired. Open Live to obtain a new reading."
            case .missing: explanation = "This saved widget reading is no longer available. Open Live to obtain a new reading."
            }
        } catch { explanation = "The saved widget reading could not be read. Reopen Hearth to try again." }
    }
    private func revalidate() {
        guard let ticket else { return }
        // Origin retirement is sticky for this scene; returning from Settings cannot silently adopt it.
        guard status != .originChanged, status != .expired else { return }
        status = alarmReadingsStatus(ticket, context: inert ? nil : HaConfigStore.context())
    }
}
