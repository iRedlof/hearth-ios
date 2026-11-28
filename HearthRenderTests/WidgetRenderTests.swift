import XCTest

/// Every widget fixture in the parity catalog (`-parityState <id> -parityFlush`), which pins the card
/// flush to the top-left on a magenta key colour so the host crops a fixed rect. Each id is drawn
/// twice, in light: at 364×170 in the default Card style, and at 329×155 with Larger text (the
/// smallest medium widget with the biggest type, where things stop fitting first).
///
/// The ids come from the app's own `ParityCatalog` (`-parityList`), so the walk follows the catalog.
/// `test00Index` reads them and saves the list in the runner's Documents/renders; the numbered batch
/// methods each render `idsPerBatch` of them. `scripts/render/run_all.sh` runs the index, works out
/// how many batches the list needs, and reboots the simulator between them (its renderer goes black
/// after roughly 20 launches; a batch makes 10, plus one more if it has to read the list itself).
@MainActor
final class WidgetRenderTests: XCTestCase {
    override func setUp() async throws {
        continueAfterFailure = true
        Render.beginTest()
    }

    /// Two launches per id. `run_all.sh` reads this constant to count the batches.
    static let idsPerBatch = 5
    /// The numbered methods below: `testBatch00` … `testBatch59`.
    static let batchCount = 60

    private struct Variant {
        let name: String
        let width: Int
        let height: Int
        let cardStyle: String?
    }

    private let variants = [
        Variant(name: "normal", width: 364, height: 170, cardStyle: nil),
        Variant(name: "larger", width: 329, height: 155, cardStyle: "status,text=larger")
    ]

    // MARK: - The id list

    private var idsFile: URL { Render.outputDir.appendingPathComponent("parity-ids.txt") }

    /// Asks the app for its catalog (one launch) and saves the answer for the batches.
    @discardableResult
    private func readIDsFromApp() -> [String] {
        let app = Render.launch(["-parityList"], appearance: .light, demoHouse: false)
        defer { app.terminate() }
        let count = app.staticTexts["parityRenderCount"]
        guard count.waitForExistence(timeout: 20), let expected = Int(count.label) else {
            XCTFail("The app did not show its parity catalog (-parityList)")
            return []
        }
        let ids = app.staticTexts.matching(identifier: "parityRenderIDs").allElementsBoundByIndex
            .flatMap { $0.label.split(separator: " ").map(String.init) }
        XCTAssertEqual(ids.count, expected, "Read \(ids.count) of the catalog's \(expected) ids")
        XCTAssertLessThanOrEqual(ids.count, Self.batchCount * Self.idsPerBatch,
            "The catalog has more ids than the batch methods cover: add testBatch methods")
        do { try Data(ids.joined(separator: "\n").utf8).write(to: idsFile) }
        catch { XCTFail("Could not save the id list: \(error)") }
        return ids
    }

    private func savedIDs() -> [String] {
        guard let text = try? String(contentsOf: idsFile, encoding: .utf8) else { return [] }
        return text.split(separator: "\n").map(String.init)
    }

    // MARK: - Rendering

    private func run(batch: Int) {
        var ids = savedIDs()
        if ids.isEmpty { ids = readIDsFromApp() }   // run on its own, before any index
        let lower = batch * Self.idsPerBatch
        guard lower < ids.count else { return }
        for id in ids[lower..<min(lower + Self.idsPerBatch, ids.count)] {
            for variant in variants { render(id, variant) }
        }
    }

    private func render(_ id: String, _ variant: Variant) {
        var args = ["-parityState", id, "-parityFlush",
                    "-parityWidth", "\(variant.width)", "-parityHeight", "\(variant.height)"]
        if let style = variant.cardStyle { args += ["-parityCardStyle", style] }
        let app = Render.launch(args, appearance: .light, demoHouse: false)
        Render.settle(1.4)
        Render.shot("w-\(id)-\(variant.name)", group: "WIDGET",
                    reached: "-parityState \(id) \(variant.width)x\(variant.height)"
                        + (variant.cardStyle.map { " -parityCardStyle \($0)" } ?? ""),
                    shows: "\(id) · \(variant.name)",
                    source: "widget fixture crop=\(variant.width)x\(variant.height)")
        app.terminate()
    }

    /// 1 launch: the catalog's ids, saved for the batches.
    func test00Index() { readIDsFromApp() }

    // 10 launches each.
    func testBatch00() { run(batch: 0) }
    func testBatch01() { run(batch: 1) }
    func testBatch02() { run(batch: 2) }
    func testBatch03() { run(batch: 3) }
    func testBatch04() { run(batch: 4) }
    func testBatch05() { run(batch: 5) }
    func testBatch06() { run(batch: 6) }
    func testBatch07() { run(batch: 7) }
    func testBatch08() { run(batch: 8) }
    func testBatch09() { run(batch: 9) }
    func testBatch10() { run(batch: 10) }
    func testBatch11() { run(batch: 11) }
    func testBatch12() { run(batch: 12) }
    func testBatch13() { run(batch: 13) }
    func testBatch14() { run(batch: 14) }
    func testBatch15() { run(batch: 15) }
    func testBatch16() { run(batch: 16) }
    func testBatch17() { run(batch: 17) }
    func testBatch18() { run(batch: 18) }
    func testBatch19() { run(batch: 19) }
    func testBatch20() { run(batch: 20) }
    func testBatch21() { run(batch: 21) }
    func testBatch22() { run(batch: 22) }
    func testBatch23() { run(batch: 23) }
    func testBatch24() { run(batch: 24) }
    func testBatch25() { run(batch: 25) }
    func testBatch26() { run(batch: 26) }
    func testBatch27() { run(batch: 27) }
    func testBatch28() { run(batch: 28) }
    func testBatch29() { run(batch: 29) }
    func testBatch30() { run(batch: 30) }
    func testBatch31() { run(batch: 31) }
    func testBatch32() { run(batch: 32) }
    func testBatch33() { run(batch: 33) }
    func testBatch34() { run(batch: 34) }
    func testBatch35() { run(batch: 35) }
    func testBatch36() { run(batch: 36) }
    func testBatch37() { run(batch: 37) }
    func testBatch38() { run(batch: 38) }
    func testBatch39() { run(batch: 39) }
    func testBatch40() { run(batch: 40) }
    func testBatch41() { run(batch: 41) }
    func testBatch42() { run(batch: 42) }
    func testBatch43() { run(batch: 43) }
    func testBatch44() { run(batch: 44) }
    func testBatch45() { run(batch: 45) }
    func testBatch46() { run(batch: 46) }
    func testBatch47() { run(batch: 47) }
    func testBatch48() { run(batch: 48) }
    func testBatch49() { run(batch: 49) }
    func testBatch50() { run(batch: 50) }
    func testBatch51() { run(batch: 51) }
    func testBatch52() { run(batch: 52) }
    func testBatch53() { run(batch: 53) }
    func testBatch54() { run(batch: 54) }
    func testBatch55() { run(batch: 55) }
    func testBatch56() { run(batch: 56) }
    func testBatch57() { run(batch: 57) }
    func testBatch58() { run(batch: 58) }
    func testBatch59() { run(batch: 59) }
}
