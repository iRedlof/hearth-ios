import SwiftUI
import AppIntents
import HearthKit

/// The Favourites widget (medium, two-panel). Rail: "2 on" over "of 4", warm while any favourite
/// is on. Body: up to four tiles that toggle, or run for a script (`FavToggleIntent`). When Home
/// Assistant can't be reached the favourites stay listed as Unavailable and take no tap.
public struct FavouritesPanelView: View {
    public let snap: FavSnapshot
    public init(_ snap: FavSnapshot) { self.snap = snap }

    public var body: some View {
        BeaconTilePanelView(panel: favouritesPanel(snap), title: "Favourites", kind: "com.rohit.hearth.favourites",
                            shape: .tile) { FavToggleIntent($0.id, turnOn: $0.turnOn) }
    }
}
