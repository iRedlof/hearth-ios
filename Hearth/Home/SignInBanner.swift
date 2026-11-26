import SwiftUI
import HearthKit

/// Amber banner shown when a connection needs sign-in.
/// Displays a warning message with a "Sign in" action button.
struct SignInBanner: View {
    private let message: String
    private let onFix: () -> Void

    @Environment(\.colorScheme) private var scheme

    init(message: String, onFix: @escaping () -> Void) {
        self.message = message
        self.onFix = onFix
    }

    var body: some View {
        Button {
            onFix()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(HearthColor.amber(scheme))

                Text(message)
                    .font(HearthFont.rowTitle.font)
                    .foregroundStyle(HearthColor.ink(scheme))
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 8)

                Text("Sign in")
                    .font(HearthFont.button.font)
                    .foregroundStyle(HearthColor.amber(scheme))
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(HearthColor.amberBg(scheme))
            .clipShape(RoundedRectangle(cornerRadius: HearthMetrics.groupRadius, style: .continuous))
            .padding(.horizontal, HearthMetrics.groupInset)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Previews

#Preview("Sign-in banner — Light") {
    SignInBanner(
        message: "ChargePoint needs sign-in to sync your sessions",
        onFix: {}
    )
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(HearthColor.page(.light))
    .preferredColorScheme(.light)
}

#Preview("Sign-in banner — Dark") {
    SignInBanner(
        message: "ChargePoint needs sign-in to sync your sessions",
        onFix: {}
    )
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(HearthColor.page(.dark))
    .preferredColorScheme(.dark)
}

#Preview("Long message — Light") {
    SignInBanner(
        message: "Home Assistant connection has expired and needs re-authentication to continue syncing your devices and automations",
        onFix: {}
    )
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(HearthColor.page(.light))
    .preferredColorScheme(.light)
}

#Preview("Long message — Dark") {
    SignInBanner(
        message: "Home Assistant connection has expired and needs re-authentication to continue syncing your devices and automations",
        onFix: {}
    )
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(HearthColor.page(.dark))
    .preferredColorScheme(.dark)
}
