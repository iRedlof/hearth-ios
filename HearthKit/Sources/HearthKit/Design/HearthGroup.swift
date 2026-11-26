import SwiftUI

/// A labeled card container for settings rows.
/// Renders an optional uppercase label above a rounded card.
/// Rows are stacked vertically with hairline dividers between them.
public struct HearthGroup<Content: View>: View {
    private let label: String?
    @ViewBuilder private let content: () -> Content

    @Environment(\.colorScheme) private var scheme

    public init(_ label: String? = nil, @ViewBuilder content: @escaping () -> Content) {
        self.label = label
        self.content = content
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let label = label {
                Text(label.uppercased())
                    .font(HearthFont.groupLabel.font)
                    .foregroundStyle(HearthColor.sub(scheme))
                    .padding(.horizontal, HearthMetrics.groupInset)
            }

            VStack(spacing: 0) {
                content()
            }
            .background(HearthColor.card(scheme))
            .clipShape(RoundedRectangle(cornerRadius: HearthMetrics.groupRadius))
            .padding(.horizontal, HearthMetrics.groupInset)
        }
    }
}

// MARK: - Row Divider

extension View {
    /// Adds a HearthGroup divider above this view (use for rows after the first).
    public func hearthDivider(_ scheme: ColorScheme) -> some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(HearthColor.line(scheme))
                .frame(height: 1)
                .padding(.leading, HearthMetrics.dividerInset)
            self
        }
    }
}
