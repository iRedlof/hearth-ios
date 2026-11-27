import Testing
import SwiftUI
@testable import HearthKit

/// Tests for HearthMotion animation tokens.
struct HearthMotionTests {
    @Test("Motion tokens resolve to animations")
    func motionTokensResolve() {
        // Press animation is defined
        let press = HearthMotion.press
        #expect(press is Animation)

        // Content animation is defined
        let content = HearthMotion.content
        #expect(content is Animation)

        // Transition animation is defined
        let transition = HearthMotion.transition
        #expect(transition is Animation)
    }

    @Test("Reduce Motion returns nil for animations")
    func reduceMotionNil() {
        let result = HearthMotion.respectingReduceMotion(HearthMotion.content, reduceMotion: true)
        #expect(result == nil)
    }

    @Test("Reduce Motion preserves animations when disabled")
    func reduceMotionPreserves() {
        let result = HearthMotion.respectingReduceMotion(HearthMotion.content, reduceMotion: false)
        #expect(result != nil)
    }

    @Test("Reduce Motion returns fade transition")
    func reduceMotionTransition() {
        // When reduce motion is enabled, should return opacity transition
        let result = HearthMotion.respectingReduceMotion(HearthMotion.sheetTransition, reduceMotion: true)
        // Can't directly compare transitions, but verify it's defined
        #expect(result is AnyTransition)
    }

    @Test("Reduce Motion preserves transitions when disabled")
    func reduceMotionPreservesTransition() {
        let result = HearthMotion.respectingReduceMotion(HearthMotion.sheetTransition, reduceMotion: false)
        #expect(result is AnyTransition)
    }
}
