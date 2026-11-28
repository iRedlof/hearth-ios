import XCTest

/// Places the ChargePoint widget on the simulator's Home Screen, so the real WidgetKit rendering
/// (live timers, button taps) can be looked at. Springboard automation is best-effort; every step
/// records what it saw so a failure says where the Home Screen UI differed.
@MainActor
final class WidgetPlacementTests: XCTestCase {
    func testPlaceChargePointWidget() {
        let app = XCUIApplication()
        app.launchArguments = ["-parityState", "chargepoint-offer", "-parityWidgetKit"]
        app.launch()
        Thread.sleep(forTimeInterval: 2)
        XCUIDevice.shared.press(.home)
        Thread.sleep(forTimeInterval: 1.5)
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        // Long-press an empty area to enter edit mode.
        let start = springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.62))
        start.press(forDuration: 1.6)
        Thread.sleep(forTimeInterval: 1.0)
        dump(springboard, "after long press")
        let edit = springboard.buttons["Edit"].firstMatch
        if edit.waitForExistence(timeout: 3) { edit.tap(); Thread.sleep(forTimeInterval: 0.8) }
        dump(springboard, "after Edit")
        for name in ["Add Widget", "Add Widgets", "Add widget"] {
            let item = springboard.buttons[name].firstMatch
            if item.exists { item.tap(); break }
        }
        Thread.sleep(forTimeInterval: 1.5)
        dump(springboard, "gallery")
        let search = springboard.searchFields.firstMatch
        if search.waitForExistence(timeout: 4) { search.tap(); search.typeText("Hearth"); Thread.sleep(forTimeInterval: 1.5) }
        dump(springboard, "after search")
        let hearth = springboard.cells["Hearth"].firstMatch
        guard hearth.waitForExistence(timeout: 3) else { return XCTFail("Hearth not in the widget gallery") }
        hearth.tap()
        Thread.sleep(forTimeInterval: 1.5)
        dump(springboard, "Hearth widgets")
        // Page through Hearth's widgets until the ChargePoint one is showing.
        for page in 0..<14 {
            let visible = springboard.staticTexts.allElementsBoundByIndex.map { $0.label }
            if visible.contains(where: { $0.localizedCaseInsensitiveContains("ChargePoint") }) {
                print("PLACEMENT found ChargePoint on page \(page): \(visible)")
                break
            }
            springboard.swipeLeft()
            Thread.sleep(forTimeInterval: 0.7)
        }
        dump(springboard, "before add")
        // The gallery's button is labelled " Add Widget" (leading space), so match by content.
        let add = springboard.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'Add Widget'")).firstMatch
        XCTAssertTrue(add.exists, "No Add Widget button in the gallery")
        if add.exists { add.tap() }
        Thread.sleep(forTimeInterval: 1.5)
        dump(springboard, "after add")
        let done = springboard.buttons["Done"].firstMatch
        if done.exists { done.tap() }
        Thread.sleep(forTimeInterval: 1.0)
        dump(springboard, "placed")
    }

    private func dump(_ app: XCUIApplication, _ title: String) {
        let buttons = app.buttons.allElementsBoundByIndex.prefix(40).map { $0.label }.filter { !$0.isEmpty }
        let cells = app.cells.allElementsBoundByIndex.prefix(30).map { $0.label }.filter { !$0.isEmpty }
        let texts = app.staticTexts.allElementsBoundByIndex.prefix(30).map { $0.label }.filter { !$0.isEmpty }
        print("PLACEMENT [\(title)] buttons=\(buttons) cells=\(cells) texts=\(texts)")
    }
}
