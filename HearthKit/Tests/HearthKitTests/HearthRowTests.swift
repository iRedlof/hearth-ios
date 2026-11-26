import Testing
import SwiftUI
@testable import HearthKit

@Suite("HearthRow Tests")
struct HearthRowTests {

    @Test("Subtitle uses amber when warn is true")
    func subtitleWarnUsesAmber() {
        // Light mode: warn = true → amber
        #expect(HearthRow<EmptyView>.resolvedSubtitleARGB(warn: true, .light) == HearthColor.amberLight)
        // Light mode: warn = false → sub
        #expect(HearthRow<EmptyView>.resolvedSubtitleARGB(warn: false, .light) == HearthColor.subLight)

        // Dark mode: warn = true → amber
        #expect(HearthRow<EmptyView>.resolvedSubtitleARGB(warn: true, .dark) == HearthColor.amberDark)
        // Dark mode: warn = false → sub
        #expect(HearthRow<EmptyView>.resolvedSubtitleARGB(warn: false, .dark) == HearthColor.subDark)
    }
}
