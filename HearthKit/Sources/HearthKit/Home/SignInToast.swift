import Foundation

/// Returns the toast message for a sign-in-restored event, or nil if no widgets recovered.
///
/// - Parameter recoveredCount: Number of widgets that were paused (needsSignIn) and are now live.
/// - Returns: Toast message string, or nil if count is 0.
public func signedInToastMessage(recoveredCount: Int) -> String? {
    guard recoveredCount > 0 else { return nil }
    let widgetWord = recoveredCount == 1 ? "widget" : "widgets"
    return "Signed in · \(recoveredCount) \(widgetWord) live again"
}

/// Counts how many widgets recovered from needsSignIn state after a sign-in transition.
///
/// - Parameters:
///   - previousHealth: Widget health states before sign-in (while signed out).
///   - currentHealth: Widget health states after sign-in.
/// - Returns: Count of widgets that were .needsSignIn and are now not .needsSignIn.
public func countRecoveredWidgets(
    previousHealth: [HomeWidgetKind: WidgetHealth],
    currentHealth: [HomeWidgetKind: WidgetHealth]
) -> Int {
    let kinds = Set(previousHealth.keys).union(currentHealth.keys)
    return kinds.filter { kind in
        previousHealth[kind] == .needsSignIn && currentHealth[kind] != .needsSignIn
    }.count
}
