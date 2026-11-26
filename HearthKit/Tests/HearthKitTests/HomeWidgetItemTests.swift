import Testing
@testable import HearthKit

@Suite("HomeWidgetItem Sorting")
struct HomeWidgetItemTests {

    @Test("sortedProblemsFirst: problems come before ok items")
    func problemsFirst() {
        let items = [
            HomeWidgetItem(
                id: "car",
                kind: .car,
                stateLine: "All good",
                health: .ok,
                route: .widget(.car)
            ),
            HomeWidgetItem(
                id: "alarm",
                kind: .alarm,
                stateLine: "Stale data",
                health: .stale,
                route: .widget(.alarm)
            ),
            HomeWidgetItem(
                id: "lights",
                kind: .lights,
                stateLine: "On",
                health: .ok,
                route: .widget(.lights)
            ),
            HomeWidgetItem(
                id: "chargePoint",
                kind: .chargePoint,
                stateLine: "Sign in required",
                health: .needsSignIn,
                route: .widget(.chargePoint)
            ),
        ]

        let sorted = sortedProblemsFirst(items)

        // needsSignIn and stale should come first (both sortsFirst)
        // needsSignIn > stale by severity
        #expect(sorted[0].health == .needsSignIn)
        #expect(sorted[1].health == .stale)

        // ok items should follow in their original order
        #expect(sorted[2].kind == .car)
        #expect(sorted[3].kind == .lights)
    }

    @Test("sortedProblemsFirst: stable sort preserves order within same health")
    func stableSort() {
        let items = [
            HomeWidgetItem(
                id: "car",
                kind: .car,
                stateLine: "Ready",
                health: .ok,
                route: .widget(.car)
            ),
            HomeWidgetItem(
                id: "thermostat",
                kind: .thermostat,
                stateLine: "72°",
                health: .ok,
                route: .widget(.thermostat)
            ),
            HomeWidgetItem(
                id: "lights",
                kind: .lights,
                stateLine: "On",
                health: .ok,
                route: .widget(.lights)
            ),
        ]

        let sorted = sortedProblemsFirst(items)

        // All .ok items should maintain their original order
        #expect(sorted[0].kind == .car)
        #expect(sorted[1].kind == .thermostat)
        #expect(sorted[2].kind == .lights)
    }

    @Test("sortedProblemsFirst: empty array returns empty")
    func emptyArray() {
        let items: [HomeWidgetItem] = []
        let sorted = sortedProblemsFirst(items)
        #expect(sorted.isEmpty)
    }

    @Test("sortedProblemsFirst: single item returns unchanged")
    func singleItem() {
        let items = [
            HomeWidgetItem(
                id: "car",
                kind: .car,
                stateLine: "Ready",
                health: .ok,
                route: .widget(.car)
            )
        ]

        let sorted = sortedProblemsFirst(items)
        #expect(sorted.count == 1)
        #expect(sorted[0].kind == .car)
    }

    @Test("sortedProblemsFirst: all problems sorted by severity")
    func allProblems() {
        let items = [
            HomeWidgetItem(
                id: "paused",
                kind: .car,
                stateLine: "Paused",
                health: .paused,
                route: .widget(.car)
            ),
            HomeWidgetItem(
                id: "error",
                kind: .alarm,
                stateLine: "Error",
                health: .error,
                route: .widget(.alarm)
            ),
            HomeWidgetItem(
                id: "stale",
                kind: .lights,
                stateLine: "Stale",
                health: .stale,
                route: .widget(.lights)
            ),
        ]

        let sorted = sortedProblemsFirst(items)

        // Higher severity (higher rawValue) comes first
        #expect(sorted[0].health == .error)
        #expect(sorted[1].health == .stale)
        #expect(sorted[2].health == .paused)
    }
}
