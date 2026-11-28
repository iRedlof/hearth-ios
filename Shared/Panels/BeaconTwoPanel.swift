import SwiftUI
import HearthKit

/// The two-panel card: a rail on the left (~37% of the width, the same split as Alarm, Thermostat,
/// Car and ChargePoint) and the body on the right, which the Card style paints.
///
/// Both halves are pinned to the widget's own height. A half left to size itself grew taller than
/// the widget when its content did not fit, which pushed the rail off the top edge and cut the
/// bottom of the body; pinned, the content inside has to give way instead (`ViewThatFits`).
struct BeaconTwoPanel<Rail: View, Surface: View>: View {
    @Environment(\.cardStyle) private var cardStyle
    @ViewBuilder let rail: () -> Rail
    @ViewBuilder let surface: () -> Surface

    var body: some View {
        GeometryReader { geometry in
            let railWidth = beaconSplit(width: geometry.size.width).rail
            HStack(alignment: .top, spacing: 0) {
                rail()
                    .frame(width: railWidth, height: geometry.size.height, alignment: .topLeading)
                surface()
                    .frame(width: geometry.size.width - railWidth, height: geometry.size.height, alignment: .topLeading)
            }
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading)
            .background(CardSurfaceView(beaconLook(cardStyle).body))
            .clipped()
        }
    }
}
