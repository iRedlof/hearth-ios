import Foundation

/// Protocol defining an action that can be executed and verified.
/// Used for safety-critical operations that need retry logic with verification.
public protocol ActionExecutor: Sendable {
    /// Executes the action (e.g., lock door, arm alarm).
    func execute() async throws

    /// Verifies that the action succeeded (e.g., door is locked, alarm is armed).
    /// - Returns: `true` if the desired state is confirmed, `false` if not.
    /// - Throws: When verification cannot be performed (e.g., network unreachable).
    func verify() async throws -> Bool
}

/// Monitors an action with retry logic and alerts on final failure.
///
/// Semantics:
/// 1. Execute the action
/// 2. Wait for the system to settle (retryDelay)
/// 3. Verify the action succeeded
/// 4. If verification fails (returns `false`), retry once (steps 1-3)
/// 5. If still not verified after retry, call `onFinalFailure`
///
/// Critical behavior:
/// - `onFinalFailure` is called ONLY when `verify()` returns a definite `false`
/// - If `verify()` throws (network/unreachable), do NOT call `onFinalFailure`
/// - A thrown `verify()` means "unknown state", not "failure"
/// - If `execute()` throws, still proceed to verify (the command might have been received)
///
/// - Parameters:
///   - action: The action to execute and verify
///   - retryDelay: Time to wait between execute and verify (default 5 seconds)
///   - sleep: Injectable sleep function for testing (default uses Task.sleep)
///   - onFinalFailure: Called when action definitively fails after retry
public func monitorWithRetry(
    _ action: any ActionExecutor,
    retryDelay: Duration = .seconds(5),
    sleep: @Sendable (Duration) async -> Void = { try? await Task.sleep(for: $0) },
    onFinalFailure: @Sendable () async -> Void
) async {
    // First attempt: execute → wait → verify
    try? await action.execute()
    await sleep(retryDelay)

    if let verified = try? await action.verify(), verified {
        // Success on first attempt
        return
    }

    // First verify was false or threw - retry once
    try? await action.execute()
    await sleep(retryDelay)

    // Check verification result after retry
    do {
        let verified = try await action.verify()
        if verified {
            // Success after retry
            return
        }
        // Definite failure (verify returned false) - alert
        await onFinalFailure()
    } catch {
        // verify() threw - unknown state (network unreachable, etc.)
        // Do NOT call onFinalFailure - we can't distinguish failure from unreachable
        return
    }
}
