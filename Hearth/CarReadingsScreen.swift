import SwiftUI
import WidgetKit
import HearthKit

/// Separate injectable stores permit native fixture tests without changing the signed-in account.
struct CarReadingsRuntime: Sendable {
    let tickets: CarReadingsTicketStore?
    let state: HaStateStore?
    var request: (@Sendable () async throws -> String)?
    var reloadWidget: @MainActor @Sendable () -> String = {
        WidgetCenter.shared.reloadTimelines(ofKind: "com.rohit.hearth.car")
        return "Refresh requested. Return to your Home Screen and open the new widget reading."
    }
    static var live: Self { Self(tickets: CarReadingsStore.store, state: HaConfigStore.store) }
    func context() -> HaStoreSnapshot? { try? state?.snapshot() }
}

@MainActor final class CarReadingsScreenModel: ObservableObject {
    @Published private(set) var session: CarReadingsRouteSession?
    @Published private(set) var openingTicket: CarReadingsTicket?
    @Published private(set) var unavailable: CarReadingsRouteStatus = .unavailable
    @Published private(set) var corruptedTicket = false
    @Published private(set) var feedback: String?
    @Published var showingTeslaFailure = false
    static let teslaFailureMessage = "Tesla couldn't be opened. Install the Tesla app, or open it from your Home Screen."
    private let request: CarReadingsRequest
    private let runtime: CarReadingsRuntime
    private var task: Task<Void, Never>?
    private var active = true

    init(request: CarReadingsRequest, runtime: CarReadingsRuntime) {
        self.request = request
        self.runtime = runtime
        if request.destination == .storageUnavailable { unavailable = .storageUnavailable }
    }

    var status: CarReadingsRouteStatus { session?.status ?? unavailable }
    var refreshing: Bool { session?.refreshing == true }
    var detail: CarDetailedReadings? { session.map { Self.detail($0.shownTicket) } }
    var unsavedWidgetReading: Bool { request.destination == .storageUnavailable }

    static func detail(_ ticket: CarReadingsTicket) -> CarDetailedReadings {
        CarDetailedReadings(origin: ticket.origin, cache: ticket.cache,
            error: ticket.error, setup: ticket.setup)
    }

    func load() {
        guard active else { return }
        if unsavedWidgetReading {
            unavailable = .storageUnavailable
            return
        }
        guard session == nil, let id = request.ticketID else { return }
        guard let tickets = runtime.tickets else { unavailable = .storageUnavailable; return }
        do {
            switch try tickets.lookup(id) {
            case .available(let ticket):
                openingTicket = ticket
                session = CarReadingsRouteSession(ticket: ticket, context: runtime.context())
            case .expired: unavailable = .expired
            case .missing: unavailable = .unavailable
            }
        } catch {
            corruptedTicket = error is DecodingError
                || error is CarReadingsTicketError
                || (error as? CocoaError)?.code == .fileReadCorruptFile
            unavailable = .storageUnavailable
        }
    }

    func revalidate() {
        guard active, session != nil else { return }
        session?.revalidate(context: runtime.context())
    }

    func refresh() {
        guard active, session != nil else { return }
        let current = runtime.context()
        session?.revalidate(context: current)
        guard let state = runtime.state, let context = current,
              let claim = session?.beginRefresh(context: context),
              let prefix = session?.shownTicket.origin.vehiclePrefix else { return }
        feedback = nil
        task = Task {
            let envelope = await fetchOwnedCarRouteEnvelope(store: state, context: context,
                expectedVehiclePrefix: prefix, request: runtime.request)
            guard active, !Task.isCancelled else { return }
            var candidate: CarReadingsTicket?
            var failure = envelope.result.error
            if envelope.origin.status != .obsolete && envelope.origin.status != .storageUnavailable {
                do {
                    let ticket = try CarReadingsTicket(envelope: envelope)
                    guard let tickets = runtime.tickets else { throw CarReadingsTicketError.invalid }
                    try tickets.save(ticket)
                    candidate = ticket
                } catch { failure = "The refreshed reading couldn't be saved. Try again." }
            }
            let accepted = session?.finishRefresh(claim: claim, ticket: candidate,
                context: runtime.context()) == true
            if accepted { feedback = nil }
            else if status == .current { feedback = failure ?? "Refresh did not replace this reading. Try again." }
            task = nil
        }
    }

    func close() {
        active = false
        session?.close()
        task?.cancel()
        task = nil
    }

    func requestedWidgetRefresh() {
        guard active else { return }
        feedback = runtime.reloadWidget()
    }

    func externalResult(_ opened: Bool) {
        guard active else { return }
        revalidate()
        if !opened {
            feedback = Self.teslaFailureMessage
            showingTeslaFailure = true
        }
    }
}

struct CarReadingsScreen: View {
    @StateObject private var model: CarReadingsScreenModel
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL
    let onClose: () -> Void
    let onSettings: () -> Void
    let onReconnect: () -> Void

    init(request: CarReadingsRequest, runtime: CarReadingsRuntime = .live,
         onClose: @escaping () -> Void, onSettings: @escaping () -> Void,
         onReconnect: @escaping () -> Void) {
        _model = StateObject(wrappedValue: CarReadingsScreenModel(request: request, runtime: runtime))
        self.onClose = onClose
        self.onSettings = onSettings
        self.onReconnect = onReconnect
    }

    var body: some View {
        NavigationStack {
            Form {
                if let detail = model.detail {
                    Section {
                        Text(detail.title).font(.title2.bold())
                        Text(detail.attention.title).font(.headline)
                        if let message = detail.attention.message, message != detail.error {
                            Text(message).foregroundStyle(.secondary)
                        }
                        Text(model.openingTicket?.id == model.session?.shownTicket.id
                            ? "The reading this widget opened." : "Refreshed reading. The original widget record is retained below.")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                    Section {
                        Image("CarPremium")
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: .infinity, maxHeight: 160)
                            .accessibilityHidden(true)
                    }
                    readingSources(detail)
                }
                if model.status != .current {
                    Section("Reading availability") {
                        Text(availabilityMessage).fixedSize(horizontal: false, vertical: true)
                    }
                }
                if let detail = model.detail, let error = detail.error {
                    Section("Read error") { Text(error).fixedSize(horizontal: false, vertical: true) }
                }
                if case .failure(let message, _) = model.session?.shownTicket.reply,
                   message != model.detail?.error {
                    Section("Home Assistant response") { Text(message).fixedSize(horizontal: false, vertical: true) }
                }
                actions
                if let feedback = model.feedback {
                    Section("Result") { Text(feedback).fixedSize(horizontal: false, vertical: true) }
                }
                if let detail = model.detail { readingSections(detail) }
                if let original = model.openingTicket, original.id != model.session?.shownTicket.id {
                    Section("Original widget record") {
                        Text("Refresh shows a newer reading above. The widget's opening record is retained below.")
                        DisclosureGroup("Show original readings") {
                            originalRows(original)
                        }
                    }
                }
                Section("Connection") {
                    Button(action: leaveForSettings) { controlLabel("Home Assistant settings", symbol: "gearshape") }
                }
            }
            .navigationTitle("Car readings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { model.close(); onClose() } label: { Text("Close").frame(minHeight: 44) }
                }
            }
        }
        .presentationDetents([.large])
        .task { model.load() }
        .onChange(of: scenePhase) { if scenePhase == .active { model.revalidate() } }
        .onDisappear { model.close() }
        .alert("Couldn't open Tesla", isPresented: $model.showingTeslaFailure) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Install Tesla or open it from your Home Screen.")
        }
    }

    private var actions: some View {
        Section("Actions") {
            if model.status == .current {
                Button { model.refresh() } label: {
                    controlLabel(model.refreshing ? "Refreshing…" : "Refresh", symbol: "arrow.clockwise")
                }.disabled(model.refreshing)
                Button {
                    model.revalidate()
                    guard model.status == .current else { return }
                    openURL(URL(string: "tesla://")!) { model.externalResult($0) }
                } label: { controlLabel("Open Tesla", symbol: "arrow.up.forward.app") }
                Text("Opens the Tesla app. Check the selected vehicle there.")
                    .font(.subheadline).foregroundStyle(.secondary)
            } else {
                Button { model.requestedWidgetRefresh() } label: {
                    controlLabel("Refresh widget", symbol: "arrow.clockwise")
                }
                Text("Open the new reading from your Home Screen after the widget updates.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            if model.detail?.originStatus == .authenticationFailure {
                Button { model.close(); onReconnect() } label: {
                    controlLabel("Sign in again", symbol: "person.crop.circle")
                }
            } else if model.detail?.setup == true {
                Button(action: leaveForSettings) { controlLabel("Connect Home Assistant", symbol: "house") }
            }
        }
    }

    @ViewBuilder private func readingSections(_ detail: CarDetailedReadings) -> some View {
        ForEach(detail.cohorts) { cohort in
            ForEach(cohort.sections) { section in
                Section(cohort.attribution == .historical ? "\(cohort.title) · \(section.title)" : section.title) {
                    ForEach(section.rows) { readingRow($0) }
                }
            }
        }
    }

    @ViewBuilder private func readingSources(_ detail: CarDetailedReadings) -> some View {
        Section("Reading source") {
            ForEach(detail.sourceRows) { readingRow($0) }
            Text(detail.sourceNote).font(.subheadline).foregroundStyle(.secondary)
        }
        ForEach(detail.cohorts) { cohort in
            Section(cohort.title) { ForEach(cohort.sourceRows) { readingRow($0) } }
        }
    }

    private func originalRows(_ ticket: CarReadingsTicket) -> some View {
        let detail = CarReadingsScreenModel.detail(ticket)
        return VStack(alignment: .leading, spacing: 20) {
            if let error = detail.error { Text(error).fixedSize(horizontal: false, vertical: true) }
            if case .failure(let message, _) = ticket.reply, message != detail.error {
                Text(message).fixedSize(horizontal: false, vertical: true)
            }
            ForEach(detail.sourceRows) { readingRow($0) }
            Text(detail.sourceNote).font(.subheadline).foregroundStyle(.secondary)
            ForEach(detail.cohorts) { cohort in
                Text("Original record · \(cohort.title)").font(.headline)
                ForEach(cohort.sourceRows) { readingRow($0) }
                ForEach(cohort.sections) { section in
                    Text("Original record · \(cohort.title) · \(section.title)").font(.headline)
                    ForEach(section.rows) { readingRow($0) }
                }
            }
        }
    }

    private func readingRow(_ row: CarDetailedReadingRow) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(row.label).font(.subheadline).foregroundStyle(.secondary)
            Text(row.value).font(.body).fixedSize(horizontal: false, vertical: true)
            if let note = row.note {
                Text(note).font(.subheadline).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }.padding(.vertical, 4).accessibilityElement(children: .combine)
    }

    private func controlLabel(_ title: String, symbol: String) -> some View {
        Label(title, systemImage: symbol).font(.body.weight(.semibold))
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
    }

    private func leaveForSettings() { model.close(); onSettings() }

    private var recordDescription: String {
        model.openingTicket?.id == model.session?.shownTicket.id
            ? "These are the original widget readings." : "These are the readings from your last refresh."
    }

    private var availabilityMessage: String {
        switch model.status {
        case .current: ""
        case .explanationOnly: "This widget had no identified vehicle. Connect or check Home Assistant, then refresh the widget and open its new reading."
        case .configurationChanged: "The Home Assistant connection or widget vehicle changed. \(recordDescription) Refresh and Open Tesla are unavailable for this old route."
        case .targetUnavailable: "The current widget vehicle can't be verified. \(recordDescription) Refresh the widget and open its new reading."
        case .storageUnavailable:
            if model.unsavedWidgetReading {
                "This widget reading couldn't be saved. Refresh the widget, then open its new reading."
            } else if model.corruptedTicket {
                "This saved widget reading is damaged or unsupported. Refresh the widget and open its new reading."
            } else {
                "The shared settings or readings couldn't be read. Reopen Hearth and check Home Assistant settings."
            }
        case .expired: "This widget reading has expired. Refresh the widget and open its new reading."
        case .unavailable: "This widget reading is no longer available. Refresh the widget and open its new reading."
        case .superseded: "This read was superseded. Refresh the widget and open its new reading."
        }
    }
}
