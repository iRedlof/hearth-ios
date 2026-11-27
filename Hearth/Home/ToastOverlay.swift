import SwiftUI
import HearthKit

/// Bottom toast overlay for status messages (e.g., "Signed in · 4 widgets live again").
/// Black background, white text, amber "OK" button.
struct ToastOverlay: View {
    private let message: String
    private let onDismiss: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    init(message: String, onDismiss: @escaping () -> Void) {
        self.message = message
        self.onDismiss = onDismiss
    }

    var body: some View {
        HStack(spacing: 12) {
            Text(message)
                .font(HearthFont.rowTitle.font)
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 8)

            Button {
                onDismiss()
            } label: {
                Text("OK")
                    .font(HearthFont.button.font)
                    .foregroundStyle(HearthColor.amber(colorScheme))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: HearthMetrics.groupRadius, style: .continuous)
                .fill(Color.black)
        )
        .padding(.horizontal, HearthMetrics.groupInset)
        .padding(.bottom, 20)
    }
}

// MARK: - Preview

#Preview("Light Mode") {
    ZStack {
        HearthColor.page(.light)
            .ignoresSafeArea()

        VStack {
            Spacer()
            ToastOverlay(message: "Signed in · 4 widgets live again", onDismiss: {})
        }
    }
    .preferredColorScheme(.light)
}

#Preview("Dark Mode") {
    ZStack {
        HearthColor.page(.dark)
            .ignoresSafeArea()

        VStack {
            Spacer()
            ToastOverlay(message: "Signed in · 4 widgets live again", onDismiss: {})
        }
    }
    .preferredColorScheme(.dark)
}

#Preview("Long message") {
    ZStack {
        HearthColor.page(.light)
            .ignoresSafeArea()

        VStack {
            Spacer()
            ToastOverlay(message: "Connection restored · All widgets are now updating", onDismiss: {})
        }
    }
    .preferredColorScheme(.light)
}
