import SwiftUI
import HearthKit

/// Header row for the widgets strip with "Your widgets" label and "+ Add" button.
struct YourWidgetsHeader: View {
    @Environment(\.colorScheme) private var colorScheme

    private let onAdd: () -> Void

    init(onAdd: @escaping () -> Void) {
        self.onAdd = onAdd
    }

    var body: some View {
        HStack {
            Text("Your widgets")
                .font(HearthFont.subtitle.font)
                .foregroundStyle(HearthColor.sub(colorScheme))

            Spacer()

            Button {
                onAdd()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "plus")
                        .font(.system(size: 14, weight: .semibold))
                    Text("Add")
                        .font(HearthFont.button.font)
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(
                    Capsule()
                        .fill(Color.black)
                )
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, HearthMetrics.groupInset)
    }
}

// MARK: - Preview

#Preview("Light Mode") {
    YourWidgetsHeader(onAdd: {})
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(HearthColor.page(.light))
        .preferredColorScheme(.light)
}

#Preview("Dark Mode") {
    YourWidgetsHeader(onAdd: {})
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(HearthColor.page(.dark))
        .preferredColorScheme(.dark)
}
