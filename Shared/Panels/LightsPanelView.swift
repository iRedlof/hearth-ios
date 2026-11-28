import SwiftUI
import AppIntents
import HearthKit

/// The Lights widget (medium, two-panel). Rail: "3 on" over "of 3 lights", warm while any light
/// is on. Body: up to four light tiles that toggle (`LightToggleIntent`). When Home Assistant
/// can't be reached the last-known lights stay listed as Unavailable and take no tap.
public struct LightsPanelView: View {
    public let snap: LightsSnapshot
    public init(_ snap: LightsSnapshot) { self.snap = snap }

    public var body: some View {
        BeaconTilePanelView(panel: lightsPanel(snap), title: "Lights", kind: "com.rohit.hearth.lights",
                            shape: .tile) { LightToggleIntent($0.id, on: $0.turnOn) }
    }
}
