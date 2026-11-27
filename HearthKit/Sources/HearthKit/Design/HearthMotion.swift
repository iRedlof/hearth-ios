import SwiftUI

/// Premium motion tokens for consistent, accessible animations across Hearth.
/// All animations respect Reduce Motion accessibility setting.
public enum HearthMotion {
    // MARK: - Animation Tokens

    /// Quick press animation for button/interaction feedback (100ms easeInOut).
    /// Used for: button presses, tap feedback.
    public static var press: Animation { .easeInOut(duration: 0.1) }

    /// Standard content animation for state changes (250ms easeInOut).
    /// Used for: section expand/collapse, toggles, list insert/remove, toast appear/dismiss.
    public static var content: Animation { .easeInOut(duration: 0.25) }

    /// Smooth spring for larger transitions (300ms response, 75% damping).
    /// Used for: navigation transitions, large layout changes.
    public static var transition: Animation { .spring(response: 0.3, dampingFraction: 0.75) }

    // MARK: - Transitions

    /// Standard bottom-to-top sheet transition with opacity fade.
    public static var sheetTransition: AnyTransition { .move(edge: .bottom).combined(with: .opacity) }

    /// Fade transition for conditionally-shown views.
    public static var fadeTransition: AnyTransition { .opacity }

    // MARK: - Accessibility-Aware Helpers

    /// Returns the given animation, or nil if Reduce Motion is enabled.
    /// - Parameter animation: The animation to conditionally apply.
    /// - Parameter reduceMotion: Accessibility reduce motion setting.
    /// - Returns: The animation, or nil if reduce motion is enabled.
    public static func respectingReduceMotion(
        _ animation: Animation,
        reduceMotion: Bool
    ) -> Animation? {
        reduceMotion ? nil : animation
    }

    /// Returns the given transition, or a cross-fade if Reduce Motion is enabled.
    /// - Parameter transition: The transition to conditionally apply.
    /// - Parameter reduceMotion: Accessibility reduce motion setting.
    /// - Returns: The transition, or a fade if reduce motion is enabled.
    public static func respectingReduceMotion(
        _ transition: AnyTransition,
        reduceMotion: Bool
    ) -> AnyTransition {
        reduceMotion ? .opacity : transition
    }
}

// MARK: - View Extensions

extension View {
    /// Applies content animation (250ms easeInOut) scoped to a specific value.
    /// Respects Reduce Motion accessibility setting.
    /// - Parameters:
    ///   - value: The value to observe for animation triggers.
    ///   - reduceMotion: Accessibility reduce motion setting (from environment).
    /// - Returns: Animated view.
    public func hearthContentAnimation<V: Equatable>(
        value: V,
        reduceMotion: Bool
    ) -> some View {
        animation(
            HearthMotion.respectingReduceMotion(HearthMotion.content, reduceMotion: reduceMotion),
            value: value
        )
    }

    /// Applies transition animation (300ms spring) scoped to a specific value.
    /// Respects Reduce Motion accessibility setting.
    /// - Parameters:
    ///   - value: The value to observe for animation triggers.
    ///   - reduceMotion: Accessibility reduce motion setting (from environment).
    /// - Returns: Animated view.
    public func hearthTransitionAnimation<V: Equatable>(
        value: V,
        reduceMotion: Bool
    ) -> some View {
        animation(
            HearthMotion.respectingReduceMotion(HearthMotion.transition, reduceMotion: reduceMotion),
            value: value
        )
    }
}
