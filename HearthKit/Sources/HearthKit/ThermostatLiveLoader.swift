import Foundation

/// The Shared adapter supplies one coherent journal and the existing selected-entity request path.
public struct ThermostatLiveLoader: Sendable {
    private let load: @Sendable (Date) throws -> HaStoreSnapshot
    private let merge: @Sendable (ThermostatFetchResult, ThermostatSelectionOrigin?, String, Date) throws -> HaStoreSnapshot?
    private let request: (@Sendable (String) async throws -> String)?
    public init(load: @escaping @Sendable (Date) throws -> HaStoreSnapshot,
                merge: @escaping @Sendable (ThermostatFetchResult, ThermostatSelectionOrigin?, String, Date) throws -> HaStoreSnapshot?,
                request: (@Sendable (String) async throws -> String)? = nil) {
        self.load = load; self.merge = merge; self.request = request
    }
    public func fetch(now: Date = .now) async -> ThermostatLiveEnvelope {
        guard let context = try? load(now) else { return thermostatStorageUnavailableEnvelope(now: now) }
        let captured = thermostatEnvelope(context, now: now)
        guard let origin = captured.evidence.origin, captured.evidence.configuration == .ready,
              context.climateOperation?.pending != true else { return captured }
        let result = await fetchThermostatReadings(context.config, previous: context.readings, now: now,
            request: request)
        do {
            guard let accepted = try merge(result, origin, context.climateRevision, now),
                  origin.matches(accepted) else {
                return retaining(captured, recovery: .selectionChanged, now: now)
            }
            return thermostatEnvelope(accepted, now: now)
        } catch { return retaining(captured, recovery: .readingsNotSaved, now: now) }
    }
    public func load(cause: ThermostatForegroundLoadCause, now: Date = .now) async -> ThermostatLiveEnvelope {
        switch cause {
        case .initialOrConfig, .cacheChanged, .chargepointSignIn: return cached(now: now)
        case .dashboardRefresh, .thermostatRefresh: return await fetch(now: now)
        }
    }
    public func cached(now: Date = .now) -> ThermostatLiveEnvelope {
        guard let context = try? load(now) else { return thermostatStorageUnavailableEnvelope(now: now) }
        return thermostatEnvelope(context, now: now)
    }
    /// A deliberate read owns its captured selection and callback lifetime at every await.
    public func fetch(expectedSelection: ThermostatSelectionOrigin, previous: ThermostatLiveEnvelope?,
                      isAuthorized: @escaping @Sendable () -> Bool,
                      clock: @escaping @Sendable () -> Date = { .now }) async -> ThermostatLiveEnvelope {
        let date = clock()
        let fallback = previous ?? thermostatStorageUnavailableEnvelope(now: date)
        guard let context = try? load(date) else {
            return retaining(fallback, recovery: .sharedStoreUnavailable, now: date)
        }
        guard expectedSelection.matches(context), fallback.evidence.recovery != .selectionChanged else {
            return retaining(fallback, recovery: .selectionChanged, now: date)
        }
        let captured = thermostatEnvelope(context, now: date)
        guard captured.evidence.configuration == .ready, context.climateOperation?.pending != true else { return captured }
        let revision = context.climateRevision
        let authorized: @Sendable () -> Bool = {
            guard !Task.isCancelled, isAuthorized(), let current = try? load(clock()) else { return false }
            return expectedSelection.matches(current) && current.climateRevision == revision
                && current.climateOperation?.pending != true
        }
        guard authorized(), let config = context.config else { return captured }
        let client = HaClient(config)
        let result = await fetchThermostatReadings(config, previous: context.readings, now: date, request: { id in
            guard authorized() else { throw CancellationError() }
            let json: String
            if let request { json = try await request(id) }
            else { json = try await client.stateJson(id, isAuthorized: authorized) }
            guard authorized() else { throw CancellationError() }
            return json
        })
        guard authorized() else { return retaining(captured, recovery: .selectionChanged, now: clock()) }
        do {
            guard let accepted = try merge(result, expectedSelection, revision, clock()),
                  expectedSelection.matches(accepted), isAuthorized(), !Task.isCancelled else {
                return retaining(captured, recovery: .selectionChanged, now: clock())
            }
            return thermostatEnvelope(accepted, now: clock())
        } catch { return retaining(captured, recovery: .readingsNotSaved, now: clock()) }
    }
    public func currentEnvelope(_ previous: ThermostatLiveEnvelope, now: Date = .now) -> ThermostatLiveEnvelope {
        // A retired or unbound opening cannot become today's selection by reconciliation.
        if previous.evidence.recovery == .selectionChanged { return previous }
        guard let origin = previous.evidence.origin else { return previous }
        guard let context = try? load(now) else {
            return retaining(previous, recovery: .sharedStoreUnavailable, now: now)
        }
        guard origin.matches(context), origin.entityID == previous.evidence.entityID,
              origin.resumeID == previous.evidence.resumeID,
              origin.selectedSensorIDs == previous.evidence.selectedSensorIDs else {
            return retaining(previous, recovery: .selectionChanged, now: now)
        }
        // Display reconciliation cannot erase a failed local save. A fresh explicit fetch may recover.
        if [.readingsNotSaved, .operationNotSaved].contains(previous.evidence.recovery) { return previous }
        return thermostatEnvelope(context, now: now)
    }
    private func retaining(_ previous: ThermostatLiveEnvelope, recovery: ThermostatRecovery,
                           now: Date) -> ThermostatLiveEnvelope {
        var evidence = previous.evidence
        evidence.recovery = recovery
        return ThermostatLiveEnvelope(evidence: evidence, now: now)
    }
}
