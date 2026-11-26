import SwiftUI

// MARK: - InkButtonStyle

public struct InkButtonStyle: ButtonStyle {
    nonisolated public static let height: CGFloat = HearthMetrics.buttonH

    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        InkButtonView(configuration: configuration)
    }

    private struct InkButtonView: View {
        let configuration: Configuration
        @Environment(\.colorScheme) var colorScheme

        var body: some View {
            configuration.label
                .font(HearthFont.button.font)
                .foregroundStyle(HearthColor.onAccent(colorScheme))
                .padding(.horizontal, 20)
                .frame(height: InkButtonStyle.height)
                .background(
                    Capsule()
                        .fill(HearthColor.accent(colorScheme))
                )
                .opacity(configuration.isPressed ? 0.7 : 1.0)
                .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
                .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
        }
    }
}

// MARK: - InlineRowButtonStyle

public struct InlineRowButtonStyle: ButtonStyle {
    nonisolated public static let height: CGFloat = HearthMetrics.buttonHSmall

    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        InlineRowButtonView(configuration: configuration)
    }

    private struct InlineRowButtonView: View {
        let configuration: Configuration
        @Environment(\.colorScheme) var colorScheme

        var body: some View {
            configuration.label
                .font(HearthFont.button.font)
                .foregroundStyle(HearthColor.ink(colorScheme))
                .padding(.horizontal, 16)
                .frame(height: InlineRowButtonStyle.height)
                .background(
                    Capsule()
                        .fill(HearthColor.tint(colorScheme))
                )
                .opacity(configuration.isPressed ? 0.7 : 1.0)
                .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
                .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
        }
    }
}

// MARK: - View Extensions

extension View {
    public func hearthInk() -> some View {
        buttonStyle(InkButtonStyle())
    }

    public func hearthInline() -> some View {
        buttonStyle(InlineRowButtonStyle())
    }
}

// MARK: - Preview

#Preview("Light Mode") {
    VStack(spacing: 24) {
        Button("Add to Home Screen") {}
            .hearthInk()

        Button("Test now") {}
            .hearthInline()
    }
    .padding()
    .frame(maxWidth: 400)
    .preferredColorScheme(.light)
}

#Preview("Dark Mode") {
    VStack(spacing: 24) {
        Button("Add to Home Screen") {}
            .hearthInk()

        Button("Test now") {}
            .hearthInline()
    }
    .padding()
    .frame(maxWidth: 400)
    .preferredColorScheme(.dark)
}
