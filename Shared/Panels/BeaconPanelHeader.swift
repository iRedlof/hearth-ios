import SwiftUI
import HearthKit

/// The body's header: the widget's title on the left, the shared "Checked" stamp and reload
/// button on the right. The reload button is always there. A long title at a large text size
/// shrinks a little before the stamp is given up; neither is ever cut mid-word.
struct BeaconPanelHeader: View {
    let title: String
    /// The widget kind id the reload button refreshes.
    let kind: String
    /// The time after "Checked"; nil: no stamp.
    let checked: String?
    let ink: Color
    @Environment(\.cardTextScale) private var textScale

    var body: some View {
        ViewThatFits(in: .horizontal) {
            ForEach(PanelMetrics.titleShrinkSteps, id: \.self) { step in
                row(title: fixedTitle(step), showsStamp: checked != nil)
            }
            row(title: flexibleTitle, showsStamp: false)
        }
    }

    private func row<Title: View>(title: Title, showsStamp: Bool) -> some View {
        HStack(alignment: .top, spacing: PanelMetrics.headerSpacing) {
            title
            Spacer(minLength: 2)
            BeaconFreshness(checkedAt: checked ?? "", kind: kind, ink: ink, showsStamp: showsStamp)
        }
    }

    private func titleText(_ step: CGFloat) -> some View {
        Text(title).font(.system(size: PanelMetrics.titleSize * textScale * step, weight: .bold))
            .foregroundStyle(ink).lineLimit(1)
    }

    /// At its natural width, so `ViewThatFits` can tell whether it fits beside the stamp.
    private func fixedTitle(_ step: CGFloat) -> some View { titleText(step).fixedSize() }

    private var flexibleTitle: some View {
        titleText(1).minimumScaleFactor(PanelMetrics.titleShrinkSteps.last ?? 1)
    }
}
