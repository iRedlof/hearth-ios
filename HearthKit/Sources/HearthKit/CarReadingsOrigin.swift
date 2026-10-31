import Foundation

public enum CarOriginStatus: String, Codable, Sendable {
    case readings, noReading, history, unidentified, noCar, setup, authenticationFailure, failed, obsolete, storageUnavailable
}

/// Attribution for one committed fetch, without connection URLs, tokens or display-name identity.
/// `isOperating` describes attributed current telemetry, never command authorization. A later route
/// must revalidate this scope and prefix. A known target with unknown telemetry remains `noReading`.
public struct CarReadingOrigin: Codable, Sendable, Equatable {
    public let requestScope: String?
    public let readRevision: String?
    public let vehiclePrefix: String?
    public let status: CarOriginStatus
    public let configReady: Bool
    public let observedAt: Date?
    public let displayedObservedAt: Date?
    public let attemptedAt: Date
    public let historical: Bool

    public var isOperating: Bool {
        status == .readings && configReady && vehiclePrefix != nil &&
            requestScope?.isEmpty == false && readRevision?.isEmpty == false && observedAt != nil
    }
}

/// The displayed snapshot and its full raw readings share one origin. An obsolete request's raw
/// reply remains diagnostic evidence; it never becomes the envelope's displayed vehicle.
public struct CarLiveEnvelope: Sendable, Equatable {
    public let snapshot: CarSnapshot
    public let result: CarFetchResult
    public let origin: CarReadingOrigin
    public let requestReply: Result<String, HaError>?

    /// Existing snapshot-only screens may display a newly captured current cache after an obsolete
    /// completion. This never changes the former envelope's origin or creates a route authorization.
    public func presentationSnapshot(currentContext: HaStoreSnapshot?, now: Date = .now) -> CarSnapshot {
        guard origin.status == .obsolete else { return snapshot }
        guard let currentContext else { return Self.storageUnavailable(now: now).snapshot }
        return carStoredResult(currentContext).snapshot(now: now)
    }

    public static func storageUnavailable(now: Date = .now) -> CarLiveEnvelope {
        let result = CarFetchResult(cache: nil, error: "Can't read settings · Reopen Hearth")
        return CarLiveEnvelope(snapshot: result.snapshot(now: now), result: result,
            origin: CarReadingOrigin(requestScope: nil, readRevision: nil, vehiclePrefix: nil,
                status: .storageUnavailable, configReady: false, observedAt: nil, displayedObservedAt: nil,
                attemptedAt: now, historical: false), requestReply: nil)
    }
}

private func carStoredResult(_ context: HaStoreSnapshot) -> CarFetchResult {
    guard context.config?.carReady == true else { return CarFetchResult(cache: nil, setup: true) }
    guard let stored = context.collectionCaches["car"] else { return CarFetchResult(cache: nil) }
    guard let payload = stored.payload else {
        return CarFetchResult(cache: nil, error: stored.error)
    }
    guard let readings = try? JSONDecoder().decode(CarReadingsCache.self, from: Data(payload.utf8)),
          carReplyIdentity(readings.current) != nil, stored.observedAt == readings.checkedAt else {
        return CarFetchResult(cache: nil, error: "Can't read cached car data · Refresh to check")
    }
    return CarFetchResult(cache: readings, error: stored.error)
}

private func carEnvelope(context: HaStoreSnapshot, result: CarFetchResult,
                         attemptedAt: Date, now: Date,
                         requestReply: Result<String, HaError>?,
                         override: CarOriginStatus? = nil) -> CarLiveEnvelope {
    let identity = carReplyIdentity(result.cache?.current)
    let historical = result.shownCar != nil && (result.error != nil || result.shownCar?.stale == true)
    let status: CarOriginStatus
    if let override { status = override }
    else if result.setup { status = .setup }
    else if result.error != nil {
        let unauthorized: Bool
        if case .failure(let error) = requestReply { unauthorized = error.code == 401 }
        else { unauthorized = false }
        status = unauthorized || beaconNeedsSignIn(result.error) ? .authenticationFailure : .failed
    } else if identity?.found == false { status = .noCar }
    else if identity?.vehiclePrefix == nil { status = .unidentified }
    else if result.shownCar?.stale == true { status = .history }
    else if result.currentCar?.battery == nil { status = .noReading }
    else { status = .readings }
    return CarLiveEnvelope(snapshot: result.snapshot(now: now), result: result,
        origin: CarReadingOrigin(requestScope: context.scope, readRevision: context.scope,
            vehiclePrefix: identity?.vehiclePrefix, status: status, configReady: context.config?.carReady == true,
            observedAt: result.cache?.checkedAt, displayedObservedAt: result.displayedObservedAt,
            attemptedAt: attemptedAt, historical: historical), requestReply: requestReply)
}

private func obsoleteCarEnvelope(context: HaStoreSnapshot, now: Date,
                                 requestReply: Result<String, HaError>?) -> CarLiveEnvelope {
    // Do not load replacement-account or newer-read telemetry and attach it to this former request.
    carEnvelope(context: context,
        result: CarFetchResult(cache: nil, error: "Configuration changed · Refresh to check"),
        attemptedAt: now, now: now, requestReply: requestReply, override: .obsolete)
}

/// Captures request ownership before suspension, then commits raw readings/history under the same
/// file lock as account scope. The completion clock records the actual response observation time.
public func fetchOwnedCarEnvelope(store: HaStateStore, context: HaStoreSnapshot, now: Date = .now,
                                  request: (@Sendable () async throws -> String)? = nil,
                                  observedNow: @Sendable () -> Date = { .now }) async -> CarLiveEnvelope {
    guard let config = context.config, config.carReady else {
        return carEnvelope(context: context, result: CarFetchResult(cache: nil, setup: true),
            attemptedAt: now, now: now, requestReply: nil)
    }
    var reply: Result<String, HaError>?
    var owner: HaCollectionReadOwner?
    var completedAt = now
    do {
        let current = try store.snapshot()
        guard current.scope == context.scope,
              haSameConnection(current.config, config),
              let readID = try store.beginCollectionRead("car", expectedScope: context.scope,
                expectedRevision: context.scope) else {
            return obsoleteCarEnvelope(context: context, now: now, requestReply: nil)
        }
        owner = HaCollectionReadOwner(kind: "car", scope: context.scope,
            revision: context.scope, readID: readID)
        do {
            let raw: String
            if let request { raw = try await request() }
            else { raw = try await HaClient(config).template(CAR_TEMPLATE) }
            reply = .success(raw)
        } catch is CancellationError {
            reply = .failure(HaError("Refresh interrupted"))
        } catch {
            reply = .failure(HaError(friendlyError(error), code: (error as? HaError)?.code ?? 0))
        }
        completedAt = observedNow()
        guard let reply else { return CarLiveEnvelope.storageUnavailable(now: completedAt) }
        let committedReply: Result<String, HaError> = Task.isCancelled
            ? .failure(HaError("Refresh interrupted")) : reply
        guard let committed = try store.mergeCollection("car", reply: committedReply,
            expectedScope: context.scope, expectedRevision: context.scope, readID: readID,
            now: completedAt) else {
            return obsoleteCarEnvelope(context: context, now: completedAt, requestReply: reply)
        }
        return carEnvelope(context: context, result: carStoredResult(committed),
            attemptedAt: completedAt, now: completedAt, requestReply: reply)
    } catch {
        if let owner {
            do {
                guard let failed = try store.failCollectionRead(owner,
                    error: "Can't save readings · Refresh to retry", now: completedAt) else {
                    return obsoleteCarEnvelope(context: context, now: completedAt, requestReply: reply)
                }
                return carEnvelope(context: context, result: carStoredResult(failed),
                    attemptedAt: completedAt, now: completedAt, requestReply: reply, override: .failed)
            } catch {}
        }
        // No coherent persisted cache means no operating origin, even if transport returned data.
        let result = CarFetchResult(cache: nil, error: "Can't read settings · Reopen Hearth")
        return carEnvelope(context: context, result: result, attemptedAt: completedAt,
            now: completedAt, requestReply: reply, override: .storageUnavailable)
    }
}
