import Testing
import CoreText
@testable import HearthKit

@Suite("Font registration tests")
struct HearthFontTests {

    @Test("Roboto Flex family is registered after calling registerIfNeeded")
    func test_robotoFlexFamilyIsRegistered() {
        HearthFontRegistration.registerIfNeeded()

        let availableFamilies = CTFontManagerCopyAvailableFontFamilyNames() as? [String] ?? []
        #expect(availableFamilies.contains("Roboto Flex"))
    }

    @Test("registerIfNeeded is idempotent")
    func test_registerIsIdempotent() {
        // Call twice
        HearthFontRegistration.registerIfNeeded()
        HearthFontRegistration.registerIfNeeded()

        // Should not throw and family should still be present
        let availableFamilies = CTFontManagerCopyAvailableFontFamilyNames() as? [String] ?? []
        #expect(availableFamilies.contains("Roboto Flex"))
    }
}
