import SwiftUI
import HearthKit

/// Amber banner shown when a connection needs sign-in.
/// Displays a lock icon, title, affected widgets detail, and a "Sign in" button.
struct SignInBanner: View {
    private let title: String
    private let detail: String?
    private let onFix: () -> Void

    @Environment(\.colorScheme) private var scheme

    init(title: String, detail: String? = nil, onFix: @escaping () -> Void) {
        self.title = title
        self.detail = detail
        self.onFix = onFix
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "lock.fill")
                .font(.system(size: 18))
                .foregroundStyle(HearthColor.amber(scheme))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(HearthFont.rowTitle.font)
                    .foregroundStyle(HearthColor.ink(scheme))
                    .fixedSize(horizontal: false, vertical: true)

                if let detail {
                    Text(detail)
                        .font(HearthFont.subtitle.font)
                        .foregroundStyle(HearthColor.amber(scheme))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 8)

            Button {
                onFix()
            } label: {
                Text("Sign in")
                    .font(HearthFont.button.font)
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
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(HearthColor.amberBg(scheme))
        .clipShape(RoundedRectangle(cornerRadius: HearthMetrics.groupRadius, style: .continuous))
        .padding(.horizontal, HearthMetrics.groupInset)
    }
}

// MARK: - Previews

#Preview("Sign-in banner — Light") {
    SignInBanner(
        title: "Home Assistant needs sign-in",
        detail: "Home alarm, Hallway thermostat, Lights and Stargate are paused",
        onFix: {}
    )
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(HearthColor.page(.light))
    .preferredColorScheme(.light)
}

#Preview("Sign-in banner — Dark") {
    SignInBanner(
        title: "Home Assistant needs sign-in",
        detail: "Home alarm, Hallway thermostat, Lights and Stargate are paused",
        onFix: {}
    )
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(HearthColor.page(.dark))
    .preferredColorScheme(.dark)
}

#Preview("No detail — Light") {
    SignInBanner(
        title: "ChargePoint needs sign-in",
        onFix: {}
    )
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(HearthColor.page(.light))
    .preferredColorScheme(.light)
}

#Preview("No detail — Dark") {
    SignInBanner(
        title: "ChargePoint needs sign-in",
        onFix: {}
    )
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(HearthColor.page(.dark))
    .preferredColorScheme(.dark)
}
