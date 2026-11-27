import SwiftUI
import HearthKit

/// Large "Hearth" title for the Home screen with optional overflow menu.
struct HomeHeader: View {
    @Environment(\.colorScheme) var colorScheme
    var onRefresh: (() -> Void)?
    var onSignOut: (() -> Void)?

    var body: some View {
        HStack(alignment: .top) {
            Text("Hearth")
                .font(HearthFont.largeTitle.font)
                .foregroundStyle(HearthColor.ink(colorScheme))
                .frame(maxWidth: .infinity, alignment: .leading)

            if onRefresh != nil || onSignOut != nil {
                Menu {
                    if let onRefresh {
                        Button {
                            onRefresh()
                        } label: {
                            Label("Refresh", systemImage: "arrow.clockwise")
                        }
                    }
                    if let onSignOut {
                        Button(role: .destructive) {
                            onSignOut()
                        } label: {
                            Label("Sign out", systemImage: "rectangle.portrait.and.arrow.right")
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(HearthFont.title3.font)
                        .foregroundStyle(HearthColor.ink(colorScheme).opacity(0.6))
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("More actions")
            }
        }
        .padding(.horizontal, HearthMetrics.pagePadding)
        .padding(.top, 20)
    }
}

#Preview("Light") {
    HomeHeader()
        .preferredColorScheme(.light)
}

#Preview("Dark") {
    HomeHeader()
        .preferredColorScheme(.dark)
}
