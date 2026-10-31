import Foundation

/// A settings read belongs to the account captured when its screen opens.
@MainActor
public func settingsDiscoveryJson(config: HaConfig, scope: String?,
                                  current: () -> HaStoreSnapshot?,
                                  read: (HaConfig) async throws -> String) async throws -> String {
    guard let starting = current(), settingsDiscoveryCurrent(config: config, scope: scope, current: starting),
          let latest = starting.config else {
        throw HaError("Your account changed. Reopen Settings to continue.")
    }
    try Task.checkCancellation()
    let json: String
    do {
        json = try await read(latest)
    } catch {
        try Task.checkCancellation()
        if (error as? URLError)?.code == .cancelled { throw CancellationError() }
        throw error
    }
    try Task.checkCancellation()
    guard settingsDiscoveryCurrent(config: config, scope: scope, current: current()) else {
        throw HaError("Your account changed. Reopen Settings to continue.")
    }
    return json
}

/// Entity edits within an account remain valid; replacing that account revokes the screen.
public func settingsDiscoveryCurrent(config: HaConfig, scope: String?,
                                     current: HaStoreSnapshot?) -> Bool {
    guard let scope, let current, let latest = current.config else { return false }
    return current.scope == scope && config.hasAuth && latest.hasAuth && haSameConnection(config, latest)
}
