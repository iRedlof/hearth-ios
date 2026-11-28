import SwiftUI
import AppIntents
import HearthKit

/// The Quick actions widget (medium, two-panel). Rail: "4 actions" over "Tap to run". Body: up to
/// four script chips; a tap runs the script (`QuickRunIntent`). When Home Assistant can't be
/// reached the chips stay listed as Unavailable and take no tap.
public struct QuickPanelView: View {
    public let snap: QuickSnapshot
    public init(_ snap: QuickSnapshot) { self.snap = snap }

    public var body: some View {
        BeaconTilePanelView(panel: quickPanel(snap), title: "Quick", kind: "com.rohit.hearth.quick",
                            shape: .chip) { QuickRunIntent($0.id) }
    }
}
