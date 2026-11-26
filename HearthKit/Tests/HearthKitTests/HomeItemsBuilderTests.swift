import Testing
import Foundation
@testable import HearthKit

@Suite("Home items builder") struct HomeItemsBuilderTests {
    @Test("Builds items with readings and sorts problems first")
    func buildsItemsWithReadings() throws {
        let kinds: [HomeWidgetKind] = [.car, .alarm, .lights]
        let readings: [HomeWidgetKind: WidgetReading] = [
            .car: WidgetReading(health: .stale, stateLine: "2h ago"),
            .alarm: WidgetReading(health: .ok, stateLine: "Disarmed"),
            .lights: WidgetReading(health: .error, stateLine: "Failed to load")
        ]

        let items = homeWidgetItems(kinds: kinds, readings: readings)

        #expect(items.count == 3)

        // Problems first: error (.lights) > stale (.car) > ok (.alarm)
        #expect(items[0].kind == .lights)
        #expect(items[0].health == .error)
        #expect(items[0].stateLine == "Failed to load")

        #expect(items[1].kind == .car)
        #expect(items[1].health == .stale)
        #expect(items[1].stateLine == "2h ago")

        #expect(items[2].kind == .alarm)
        #expect(items[2].health == .ok)
        #expect(items[2].stateLine == "Disarmed")
    }

    @Test("Defaults missing readings to ok health and Added stateLine")
    func defaultsMissingReadings() throws {
        let kinds: [HomeWidgetKind] = [.car, .alarm]
        let readings: [HomeWidgetKind: WidgetReading] = [
            .car: WidgetReading(health: .ok, stateLine: "Ready")
        ]

        let items = homeWidgetItems(kinds: kinds, readings: readings)

        #expect(items.count == 2)

        // Both are .ok, so original order is preserved
        #expect(items[0].kind == .car)
        #expect(items[0].stateLine == "Ready")

        #expect(items[1].kind == .alarm)
        #expect(items[1].stateLine == "Added")
        #expect(items[1].health == .ok)
    }

    @Test("Handles empty kinds array")
    func handlesEmptyKinds() throws {
        let items = homeWidgetItems(kinds: [], readings: [:])
        #expect(items.isEmpty)
    }

    @Test("Routes are set to widget(kind)")
    func routesSetToWidgetKind() throws {
        let kinds: [HomeWidgetKind] = [.car]
        let items = homeWidgetItems(kinds: kinds, readings: [:])

        #expect(items.count == 1)
        #expect(items[0].route == .widget(.car))
    }
}
