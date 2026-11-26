import Foundation
import CoreText

/// Registers the bundled Roboto Flex font with CoreText.
public enum HearthFontRegistration {

    /// Registers the bundled Roboto Flex font if not already registered.
    /// Idempotent: calling multiple times is safe and has no effect after the first successful registration.
    public static func registerIfNeeded() {
        // Guard: if Roboto Flex is already registered, no-op
        let availableFamilies = CTFontManagerCopyAvailableFontFamilyNames() as? [String] ?? []
        if availableFamilies.contains("Roboto Flex") {
            return
        }

        // Get the bundled font URL from Bundle.module
        guard let fontURL = Bundle.module.url(forResource: "RobotoFlex", withExtension: "ttf") else {
            assertionFailure("RobotoFlex.ttf not found in HearthKit bundle")
            return
        }

        // Register the font with CoreText
        var error: Unmanaged<CFError>?
        let success = CTFontManagerRegisterFontsForURL(fontURL as CFURL, .process, &error)

        if !success {
            if let error = error?.takeRetainedValue() {
                let cfError = error as Error as NSError
                // Error code 105 means "already registered" - this is OK, treat as success
                if cfError.code != 105 {
                    assertionFailure("Failed to register Roboto Flex: \(error)")
                }
            }
        }
    }
}
