import Foundation

/// The one button a body can offer when it has no items to show. Each opens Hearth through
/// `HaSetupIntent`, exactly as the flat cards' Connect / Open Settings buttons did.
public enum PanelAction: Sendable, Equatable {
    case connect, signIn, openSettings

    public var label: String {
        switch self {
        case .connect: "Connect"
        case .signIn: "Sign in"
        case .openSettings: "Open Settings"
        }
    }

    /// Whether Hearth should open on signing in again rather than on Settings.
    public var reconnect: Bool { self == .signIn }
}

/// What a body shows in place of its items: one message, and a button when the person can act.
public struct PanelPrompt: Sendable, Equatable {
    public let message: String
    public let action: PanelAction?

    public init(message: String, action: PanelAction?) {
        self.message = message; self.action = action
    }
}

/// The prompt for a snapshot, or nil when the body shows its items.
///
/// A failed read keeps its last-known items on screen, unless the failure is one only the person
/// can fix (sign in again, a missing entity): then the way back into the app comes first.
public func panelPrompt(state: TileSnapshotState, error: String?, hasItems: Bool,
                        choice: String, empty: String) -> PanelPrompt? {
    switch state {
    case .setup:
        return PanelPrompt(message: PanelCopy.connectHome, action: .connect)
    case .choose:
        return PanelPrompt(message: choice, action: .openSettings)
    case .loading:
        return PanelPrompt(message: PanelCopy.checking, action: nil)
    case .failed:
        if beaconNeedsSettings(error) {
            return PanelPrompt(message: error ?? PanelCopy.couldNotRead,
                               action: beaconNeedsSignIn(error) ? .signIn : .openSettings)
        }
        return hasItems ? nil : PanelPrompt(message: error ?? PanelCopy.couldNotRead, action: nil)
    case .ready, .empty:
        return hasItems ? nil : PanelPrompt(message: empty, action: nil)
    }
}

/// The line under the header while items are shown: why the read failed ("Can't reach Home
/// Assistant"). A prompt already carries its own message.
public func panelNotice(error: String?, prompt: PanelPrompt?) -> String? {
    prompt == nil ? error : nil
}
