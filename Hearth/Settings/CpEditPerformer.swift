import SwiftUI
import HearthKit

/// Shared helper for performing ChargePoint edits with error handling and state updates.
/// Used by both ChargePointPage and ChargePointAlertsPage to avoid code duplication.
@MainActor
struct CpEditPerformer {
    let runtime: any SettingsRuntime
    @Binding var cp: SettingsCpState
    @Binding var editError: String?
    @Binding var editID: UUID

    /// Performs a ChargePoint edit, updates state, and handles errors.
    /// - Parameters:
    ///   - edit: The edit to perform
    ///   - supplied: Optional expected origin (defaults to current cp.origin)
    func perform(_ edit: SettingsCpEdit, expected supplied: CpSettingsOrigin? = nil) {
        let expected = supplied ?? cp.origin
        let captured = UUID()
        editID = captured
        Task { @MainActor in
            do {
                let result = try await runtime.performCpEdit(edit, expected: expected)
                guard editID == captured else { return }
                cp = result
            }
            catch is CancellationError { return }
            catch {
                if editID == captured {
                    editError = friendlyError(error)
                }
            }
        }
    }
}
