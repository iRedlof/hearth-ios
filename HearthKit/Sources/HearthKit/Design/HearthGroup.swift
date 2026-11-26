import SwiftUI

/// A labeled card container for settings rows.
/// Automatically inserts hairline dividers between rows.
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
            if let label {
                Text(label.uppercased())
                    .font(HearthFont.groupLabel.font)
                    .foregroundStyle(HearthColor.sub(scheme))
                    .padding(.horizontal, HearthMetrics.groupInset + 12)
            }
            _VariadicView.Tree(HearthRowStack(scheme: scheme)) { content() }
                .background(HearthColor.card(scheme))
                .clipShape(RoundedRectangle(cornerRadius: HearthMetrics.groupRadius, style: .continuous))
                .padding(.horizontal, HearthMetrics.groupInset)
        }
    }
}

private struct HearthRowStack: _VariadicView.MultiViewRoot {
    let scheme: ColorScheme

    func body(children: _VariadicView.Children) -> some View {
        VStack(spacing: 0) {
            ForEach(children) { child in
                if child.id != children.first?.id {
                    Rectangle()
                        .fill(HearthColor.line(scheme))
                        .frame(height: 1)
                        .padding(.leading, HearthMetrics.dividerInset)
                }
                child
            }
        }
    }
}
