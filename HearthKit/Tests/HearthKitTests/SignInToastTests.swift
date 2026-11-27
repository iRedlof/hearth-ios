import Testing
@testable import HearthKit

@Suite("Sign-in toast message")
struct SignInToastTests {
    @Test("No recovered widgets returns nil")
    func noRecoveredWidgets() {
        #expect(signedInToastMessage(recoveredCount: 0) == nil)
    }

    @Test("One recovered widget uses singular")
    func oneRecoveredWidget() {
        #expect(signedInToastMessage(recoveredCount: 1) == "Signed in · 1 widget live again")
    }

    @Test("Multiple recovered widgets use plural")
    func multipleRecoveredWidgets() {
        #expect(signedInToastMessage(recoveredCount: 2) == "Signed in · 2 widgets live again")
        #expect(signedInToastMessage(recoveredCount: 5) == "Signed in · 5 widgets live again")
    }

    @Test("Count recovered widgets when all needsSignIn → healthy")
    func allRecovered() {
        let previous: [HomeWidgetKind: WidgetHealth] = [
            .car: .needsSignIn,
            .alarm: .needsSignIn,
            .thermostat: .needsSignIn
        ]
        let current: [HomeWidgetKind: WidgetHealth] = [
            .car: .ok,
            .alarm: .ok,
            .thermostat: .ok
        ]
        #expect(countRecoveredWidgets(previousHealth: previous, currentHealth: current) == 3)
    }

    @Test("Count recovered widgets when some needsSignIn → healthy")
    func someRecovered() {
        let previous: [HomeWidgetKind: WidgetHealth] = [
            .car: .needsSignIn,
            .alarm: .ok,
            .thermostat: .needsSignIn
        ]
        let current: [HomeWidgetKind: WidgetHealth] = [
            .car: .ok,
            .alarm: .ok,
            .thermostat: .ok
        ]
        #expect(countRecoveredWidgets(previousHealth: previous, currentHealth: current) == 2)
    }

    @Test("No recovery when widgets stay needsSignIn")
    func noRecoveryStillSignedOut() {
        let previous: [HomeWidgetKind: WidgetHealth] = [
            .car: .needsSignIn,
            .alarm: .needsSignIn
        ]
        let current: [HomeWidgetKind: WidgetHealth] = [
            .car: .needsSignIn,
            .alarm: .needsSignIn
        ]
        #expect(countRecoveredWidgets(previousHealth: previous, currentHealth: current) == 0)
    }

    @Test("No recovery when widgets were already ok")
    func noRecoveryAlreadyHealthy() {
        let previous: [HomeWidgetKind: WidgetHealth] = [
            .car: .ok,
            .alarm: .ok
        ]
        let current: [HomeWidgetKind: WidgetHealth] = [
            .car: .ok,
            .alarm: .ok
        ]
        #expect(countRecoveredWidgets(previousHealth: previous, currentHealth: current) == 0)
    }

    @Test("Recovery handles mixed final states")
    func recoveryWithMixedFinalStates() {
        let previous: [HomeWidgetKind: WidgetHealth] = [
            .car: .needsSignIn,
            .alarm: .needsSignIn,
            .thermostat: .needsSignIn
        ]
        let current: [HomeWidgetKind: WidgetHealth] = [
            .car: .ok,
            .alarm: .stale,
            .thermostat: .setup
        ]
        // All three recovered (not needsSignIn anymore), even though not all are .ok
        #expect(countRecoveredWidgets(previousHealth: previous, currentHealth: current) == 3)
    }

    @Test("No recovery if needsSignIn → error")
    func noRecoveryIfError() {
        let previous: [HomeWidgetKind: WidgetHealth] = [
            .car: .needsSignIn
        ]
        let current: [HomeWidgetKind: WidgetHealth] = [
            .car: .error
        ]
        #expect(countRecoveredWidgets(previousHealth: previous, currentHealth: current) == 1)
    }

    @Test("Empty health states return zero")
    func emptyStates() {
        #expect(countRecoveredWidgets(previousHealth: [:], currentHealth: [:]) == 0)
    }

    @Test("New widgets in current state don't count as recovered")
    func newWidgetsNotRecovered() {
        let previous: [HomeWidgetKind: WidgetHealth] = [
            .car: .needsSignIn
        ]
        let current: [HomeWidgetKind: WidgetHealth] = [
            .car: .ok,
            .alarm: .ok  // newly configured
        ]
        #expect(countRecoveredWidgets(previousHealth: previous, currentHealth: current) == 1)
    }
}
