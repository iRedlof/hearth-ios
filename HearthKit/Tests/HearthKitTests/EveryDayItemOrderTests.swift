import Testing
@testable import HearthKit

@Suite("EveryDayItem order")
struct EveryDayItemOrderTests {
    @Test("Display order matches approved mock sequence")
    func displayOrder() {
        let order = EveryDayItem.displayOrder
        #expect(order.count == 5)
        #expect(order[0] == .goodnight)
        #expect(order[1] == .routines)
        #expect(order[2] == .leaveBy)
        #expect(order[3] == .travelDays)
        #expect(order[4] == .safetyAlerts)
    }

    @Test("Display order contains all cases")
    func allCasesPresent() {
        let order = EveryDayItem.displayOrder
        let allCases = Set(EveryDayItem.allCases)
        let ordered = Set(order)
        #expect(ordered == allCases)
    }

    @Test("Display order has no duplicates")
    func noDuplicates() {
        let order = EveryDayItem.displayOrder
        let unique = Set(order)
        #expect(order.count == unique.count)
    }
}
