import Testing
@testable import HearthKit

@Suite("Widget display name resolution")
struct WidgetNameTests {

    @Test("Uses custom name when provided")
    func customName() {
        #expect(widgetDisplayName(custom: "My Tesla", kindDefault: "Car") == "My Tesla")
    }

    @Test("Uses default when custom is nil")
    func nilCustom() {
        #expect(widgetDisplayName(custom: nil, kindDefault: "Thermostat") == "Thermostat")
    }

    @Test("Uses default when custom is empty")
    func emptyCustom() {
        #expect(widgetDisplayName(custom: "", kindDefault: "Alarm") == "Alarm")
    }

    @Test("Uses default when custom is whitespace")
    func whitespaceCustom() {
        #expect(widgetDisplayName(custom: "  ", kindDefault: "Doors") == "Doors")
    }

    @Test("Trims custom name")
    func trimsCustom() {
        #expect(widgetDisplayName(custom: "  Office Mini  ", kindDefault: "Thermostat") == "Office Mini")
    }
}
