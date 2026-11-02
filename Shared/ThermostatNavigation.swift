import Foundation
import SwiftUI
import HearthKit

enum ThermostatReadingsStore {
    static var store: ThermostatTicketStore? {
        guard let container = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: HaConfigStore.appGroup) else { return nil }
        return ThermostatTicketStore(directory: container.appendingPathComponent("Library/Application Support/ThermostatReadings"))
    }
    static func bind(_ envelope: ThermostatLiveEnvelope, date: Date = .now,
                     store: ThermostatTicketStore? = ThermostatReadingsStore.store) -> ThermostatEntryPayload {
        bindThermostatEntry(envelope, date: date) { ticket in
            guard let store else { throw HaError("Shared storage is unavailable") }
            try store.save(ticket, now: date)
        }
    }
}

/// A scene-local adapter. Opening and revalidation have only local storage dependencies.
struct ThermostatReadingsRuntime: Sendable {
    let tickets: ThermostatTicketStore?
    let state: HaStateStore?
    var request: (@Sendable (String) async throws -> String)? = nil
    var actions: ClimateActionDependencies? = nil
    var clock: @Sendable () -> Date = { .now }
    static var live: Self { Self(tickets: ThermostatReadingsStore.store, state: HaConfigStore.store) }
    func context() -> HaStoreSnapshot? { try? state?.expireClimateOperation(now: clock()) }
}

@MainActor final class ThermostatControlsModel: ObservableObject {
    let request: ThermostatRouteRequest
    let runtime: ThermostatReadingsRuntime
    @Published private(set) var session: ThermostatRouteSession?
    @Published private(set) var explanation: String?
    @Published private(set) var checking = false
    @Published private(set) var error: String?
    @Published var picker: ClimatePick?
    private var didOpen = false
    private var refreshTask: Task<Void, Never>?
    private var refreshLifetime: ThermostatRequestLifetime?
    private var actionLifetime: ThermostatRequestLifetime?
    private var actionID: UUID?
    private let lifetime = ThermostatRequestLifetime()
    init(request: ThermostatRouteRequest, runtime: ThermostatReadingsRuntime = .live) {
        self.request = request; self.runtime = runtime
    }
    func open() {
        guard lifetime.isActive() else { return }
        if didOpen { revalidate(); return }
        didOpen = true
        guard case .ticket(let id) = request.destination else {
            explanation = "These readings weren't saved. Open Hearth's Live tab and use Refresh."; return
        }
        do {
            guard let tickets = runtime.tickets else { throw HaError("Shared storage is unavailable") }
            switch try tickets.lookup(id, now: runtime.clock()) {
            case .available(let ticket):
                var admitted = ThermostatRouteSession(ticket: ticket, context: runtime.context(), now: runtime.clock())
                let presentMode = admitted.consumeInitialModePresentation(request.purpose)
                let initialOrigin = admitted.controlOrigin
                session = admitted
                if presentMode { choose(kind: "mode", expectedOrigin: initialOrigin) }
            case .expired: explanation = "These saved readings have expired. Open Live and use Refresh."
            case .missing: explanation = "These saved readings are no longer available. Open Live and use Refresh."
            }
        } catch { explanation = "Couldn't read the saved readings. Reopen Hearth to try again." }
    }
    func revalidate() {
        guard lifetime.isActive(), var session else { return }
        session.reconcile(context: runtime.context(), now: runtime.clock()); self.session = session
        if session.status != .current {
            refreshLifetime?.invalidate(); refreshTask?.cancel(); checking = false
            actionLifetime?.invalidate(); picker = nil
        }
    }
    @discardableResult func refresh() -> Task<Void, Never>? {
        guard lifetime.isActive(), var session else { return nil }
        let taskID = UUID()
        guard let claim = session.beginRefresh(requestID: request.eventID, taskID: taskID,
            context: runtime.context(), now: runtime.clock()) else { self.session = session; return nil }
        self.session = session; checking = true; error = nil
        let owner = ThermostatRequestLifetime(); refreshLifetime = owner
        let previous = session.shownEnvelope, runtime = runtime, lifetime = lifetime
        let task = Task {
            let envelope = await ThermostatLiveSnapshot.fetchEnvelope(expectedSelection: claim.selection,
                owner: ThermostatReadOwner(id: taskID, source: .routeRefresh), previous: previous,
                isAuthorized: { owner.isActive() && lifetime.isActive() }, clock: runtime.clock, request: runtime.request)
            guard owner.isActive(), lifetime.isActive(), !Task.isCancelled, var current = self.session else { return }
            _ = current.finishRefresh(claim: claim, envelope: envelope, context: runtime.context(), now: runtime.clock())
            self.session = current; checking = false; refreshLifetime = nil; refreshTask = nil
        }
        refreshTask = task; return task
    }
    func close() {
        lifetime.invalidate(); refreshLifetime?.invalidate(); refreshTask?.cancel()
        actionLifetime?.invalidate(); session?.close(); picker = nil; checking = false
    }
    func choose(kind: String, expectedOrigin: ClimateControlOrigin? = nil) {
        revalidate()
        guard lifetime.isActive(), !checking, let origin = session?.controlOrigin,
              expectedOrigin == nil || expectedOrigin == origin,
              let state = session?.shownEnvelope.presentation.state else { return }
        let options = climateOptions(state, kind: kind)
        let current = kind == "fan" ? state.fanMode : state.mode
        guard options.contains(where: { $0 != current }) else { return }
        actionLifetime?.invalidate()
        let owner = ThermostatRequestLifetime(); actionLifetime = owner
        let pick = ClimatePick(kind: kind, options: options, current: current, scope: origin.selection.scope,
            entityID: origin.selection.entityID, revision: origin.revision, selection: origin.selection,
            expectedMode: origin.observedMode, lifetime: owner)
        picker = pick; session?.pickerID = pick.id
    }
    func dismissPicker() { if picker != nil { actionLifetime?.invalidate() }; picker = nil; session?.pickerID = nil }
    @discardableResult func select(_ pick: ClimatePick, option: String) -> Task<Void, Never>? {
        guard picker?.id == pick.id, pick.options.contains(option), pick.lifetime.isActive() else { return nil }
        picker = nil; session?.pickerID = nil
        revalidate()
        guard let origin = session?.controlOrigin, origin.selection == pick.selection,
              origin.revision == pick.revision else { return nil }
        return act(pick.kind, origin: origin, option: option)
    }
    @discardableResult func act(_ action: String, origin: ClimateControlOrigin, option: String? = nil) -> Task<Void, Never>? {
        revalidate()
        guard lifetime.isActive(), !checking, session?.controlOrigin == origin else { return nil }
        actionLifetime?.invalidate()
        let owner = ThermostatRequestLifetime(); actionLifetime = owner
        let id = UUID(); actionID = id; error = nil
        let issues = ClimateLocalIssueRecord(), lifetime = lifetime, runtime = runtime
        return Task {
            var failure: (any Error)?
            do {
                try await ClimateActionRuntime.perform(scope: origin.selection.scope, entityID: origin.selection.entityID,
                    revision: origin.revision, resumeID: origin.selection.resumeID, action: action, option: option,
                    selectionRevision: origin.selection.selectionRevision, expectedMode: origin.observedMode,
                    actionID: id, isAuthorized: { lifetime.isActive() && owner.isActive() },
                    onLocalIssue: { issues.record($0.phase) }, dependencies: runtime.actions)
            } catch { failure = error }
            guard lifetime.isActive(), owner.isActive(), actionID == id else { return }
            revalidate()
            guard session?.status == .current, let context = runtime.context(), origin.selection.matches(context) else { return }
            if let phase = issues.phase {
                session?.recordOperationSaveFailure(context: context, now: runtime.clock())
                error = climateLocalIssueMessage(phase)
            } else if let failure = failure as? ClimateActionFailure {
                if context.climateOperation?.id == failure.operationID { error = failure.message }
            } else if let failure { error = friendlyError(failure) }
        }
    }
}

/// Thermostat loading is independent of the dashboard's other-card load task.
@MainActor final class ThermostatLiveModel: ObservableObject {
    @Published private(set) var entry: ThermostatEntryPayload?
    @Published private(set) var checking = false
    private let runtime: ThermostatReadingsRuntime
    private var task: Task<Void, Never>?
    private var owner: ThermostatRequestLifetime?
    private var requestID: UUID?
    private var selection: ThermostatSelectionOrigin?
    init(runtime: ThermostatReadingsRuntime = .live) { self.runtime = runtime }
    func loadCache() {
        if checking, let selection {
            if let context = runtime.context(), selection.matches(context) { return }
            owner?.invalidate(); task?.cancel(); requestID = nil; checking = false
        }
        let context = runtime.context()
        let envelope: ThermostatLiveEnvelope
        if let previous = entry?.envelope,
           context == nil || context.map({ previous.evidence.origin?.matches($0) == true }) == true {
            envelope = ThermostatLiveSnapshot.currentEnvelope(previous, now: runtime.clock())
        } else { envelope = ThermostatLiveSnapshot.cachedEnvelope(now: runtime.clock()) }
        entry = ThermostatReadingsStore.bind(envelope, date: runtime.clock(), store: runtime.tickets)
        checking = false
    }
    @discardableResult func refresh(_ request: ThermostatRefreshRequest, source: ThermostatReadSource) -> Task<Void, Never>? {
        guard let context = runtime.context(), request.selection.matches(context), context.climateOperation?.pending != true else { return nil }
        owner?.invalidate(); task?.cancel()
        let owner = ThermostatRequestLifetime(); self.owner = owner
        requestID = request.id; selection = request.selection; checking = true
        let previous = entry?.envelope, runtime = runtime
        let task = Task {
            let envelope = await ThermostatLiveSnapshot.fetchEnvelope(expectedSelection: request.selection,
                owner: ThermostatReadOwner(id: request.id, source: source), previous: previous,
                isAuthorized: { owner.isActive() }, clock: runtime.clock, request: runtime.request)
            guard owner.isActive(), self.requestID == request.id else { return }
            entry = ThermostatReadingsStore.bind(envelope, date: runtime.clock(), store: runtime.tickets)
            checking = false; self.owner = nil; self.task = nil
        }
        self.task = task; return task
    }
    func close() { owner?.invalidate(); task?.cancel(); checking = false }
}
