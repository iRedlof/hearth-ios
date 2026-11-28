import XCTest

/// Shared plumbing for the Hearth render walker (docs/RENDER-HARNESS.md). The walker launches the
/// real app with `-demoHouse` (the DEBUG demo house) plus per-screen launch arguments, drives the
/// real UI, and writes full-screen PNGs plus a `catalog.tsv` row per image into the runner's
/// Documents/renders directory. `scripts/render/run_all.sh` copies them out and
/// `scripts/render/build_gallery.py` crops the widget frames and builds the gallery.
@MainActor enum Render {
    enum Appearance: String { case light, dark, xxxl }

    /// The simulator's renderer goes black after roughly 20 app launches without a reboot, so one
    /// test method launches at most this many times (the throwaway warm-up launch not counted).
    /// `run_all.sh` reboots the simulator between methods. Split a method that needs more.
    static let maxLaunchesPerTest = 12

    private static let launchTimeout: TimeInterval = 20
    private static let afterLaunch: TimeInterval = 1.8
    private static let afterWarmUp: TimeInterval = 3

    private static var launches = 0

    static var outputDir: URL {
        let base = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("renders", isDirectory: true)
        do { try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true) }
        catch { NSLog("[Render] cannot create \(dir.path): \(error)") }
        return dir
    }

    // MARK: - Launching

    /// Call from every test's `setUp`. Starts the launch budget and absorbs the first launch after a
    /// fresh boot, which often fails ("did not return a process handle"): a throwaway launch whose
    /// failure is expected, then a short wait.
    static func beginTest() {
        launches = 0
        let options = XCTExpectedFailure.Options()
        options.isStrict = false
        XCTExpectFailure("The first launch after a fresh boot can fail to return a process handle",
                         options: options) {
            let app = XCUIApplication()
            app.launchArguments = ["-designGallery"]
            app.launch()
            _ = app.wait(for: .runningForeground, timeout: launchTimeout)
            app.terminate()
        }
        settle(afterWarmUp)
    }

    /// Launch a fresh demo-house app with extra args and forced appearance.
    @discardableResult
    static func launch(_ extraArgs: [String], appearance: Appearance) -> XCUIApplication {
        launch(extraArgs, appearance: appearance, demoHouse: true)
    }

    @discardableResult
    static func launch(_ extraArgs: [String], appearance: Appearance, demoHouse: Bool) -> XCUIApplication {
        launches += 1
        XCTAssertLessThanOrEqual(launches, maxLaunchesPerTest,
            "This test launched the app \(launches) times; the simulator renders black after about 20. "
            + "Split it into another numbered batch method.")
        XCUIDevice.shared.appearance = appearance == .dark ? .dark : .light
        let app = XCUIApplication()
        var args = [String]()
        if demoHouse { args.append("-demoHouse") }
        args += ["-renderColorScheme", appearance == .dark ? "dark" : "light"]
        args += extraArgs
        if appearance == .xxxl {
            args += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        }
        app.launchArguments = args
        app.launch()
        if !app.wait(for: .runningForeground, timeout: launchTimeout) {
            XCTFail("The app did not reach the foreground for \(args.joined(separator: " "))")
        }
        settle(afterLaunch)
        return app
    }

    static func settle(_ seconds: TimeInterval = 1.6) { Thread.sleep(forTimeInterval: seconds) }

    // MARK: - Capture

    /// Capture the whole screen to `<name>.png` and append a catalog row.
    static func shot(_ name: String, group: String, reached: String, shows: String, source: String) {
        let data = XCUIScreen.main.screenshot().pngRepresentation
        let url = outputDir.appendingPathComponent(name + ".png")
        do { try data.write(to: url) } catch { XCTFail("Could not write \(name).png: \(error)") }
        appendCatalog(name: name, group: group, reached: reached, shows: shows, source: source)
    }

    static func appendCatalog(name: String, group: String, reached: String, shows: String, source: String) {
        let row = [name, group, reached, shows, source]
            .map { $0.replacingOccurrences(of: "\t", with: " ").replacingOccurrences(of: "\n", with: " ") }
            .joined(separator: "\t") + "\n"
        let url = outputDir.appendingPathComponent("catalog.tsv")
        do {
            if FileManager.default.fileExists(atPath: url.path) {
                let handle = try FileHandle(forWritingTo: url)
                defer { try? handle.close() }
                try handle.seekToEnd()
                try handle.write(contentsOf: Data(row.utf8))
            } else {
                try Data(row.utf8).write(to: url)
            }
        } catch { XCTFail("Could not write the catalog row for \(name): \(error)") }
    }

    /// A screen the walker could not reach: recorded in the catalog and listed in the gallery's Gaps,
    /// without failing the walk.
    static func gap(_ name: String, group: String, reason: String) {
        appendCatalog(name: name, group: group, reached: "GAP", shows: reason, source: "gap")
    }

    /// Scroll `element` to the bottom, capturing `<base>-<i>-<appearance>.png` per position.
    static func captureScroll(_ element: XCUIElement, base: String, appearance: Appearance,
                              group: String, reached: String, shows: String, source: String, maxSteps: Int = 10) {
        var index = 0
        shot("\(base)-\(index)-\(appearance.rawValue)", group: group, reached: reached,
             shows: shows + " (scroll \(index))", source: source)
        var lastHash = screenHash()
        let scroller = element.exists ? element : XCUIApplication().firstMatch
        while index < maxSteps {
            scroller.swipeUp(velocity: .slow)
            settle(0.9)
            let hash = screenHash()
            if hash == lastHash { break }
            index += 1
            shot("\(base)-\(index)-\(appearance.rawValue)", group: group, reached: reached,
                 shows: shows + " (scroll \(index))", source: source)
            lastHash = hash
        }
    }

    /// Back to the top after `captureScroll`, for the taps that follow.
    static func scrollToTop(_ element: XCUIElement, swipes: Int = 6) {
        let scroller = element.exists ? element : XCUIApplication().firstMatch
        for _ in 0..<swipes { scroller.swipeDown(velocity: .fast) }
        settle(0.8)
    }

    static func screenHash() -> String {
        let data = XCUIScreen.main.screenshot().pngRepresentation
        var hash: UInt64 = 1469598103934665603
        let stride = max(1, data.count / 4096)
        var index = 0
        while index < data.count { hash = (hash ^ UInt64(data[index])) &* 1099511628211; index += stride }
        return String(hash, radix: 16)
    }

    // MARK: - Element helpers (existence-guarded, so a missing control never aborts the walk:
    // continueAfterFailure is on and gaps are logged to the catalog).

    static func scrollView(_ app: XCUIApplication) -> XCUIElement {
        app.scrollViews.firstMatch.exists ? app.scrollViews.firstMatch : app.firstMatch
    }

    /// The first element labelled (or identified) exactly `label`.
    static func findExact(_ app: XCUIApplication, _ label: String) -> XCUIElement? {
        let exactly = NSPredicate(format: "label == %@ OR identifier == %@", label, label)
        for query in [app.buttons, app.staticTexts, app.cells, app.otherElements, app.images] {
            let element = query.matching(exactly).firstMatch
            if element.exists { return element }
        }
        return nil
    }

    /// The control to tap for `label`: labelled exactly so, else a button whose label starts with it
    /// (a settings row reads as "Title, subtitle"), else anything whose label starts with it.
    static func find(_ app: XCUIApplication, _ label: String) -> XCUIElement? {
        if let exact = findExact(app, label) { return exact }
        let starts = NSPredicate(format: "label BEGINSWITH %@", label)
        for query in [app.buttons, app.descendants(matching: .any)] {
            let element = query.matching(starts).firstMatch
            if element.exists { return element }
        }
        return nil
    }

    @discardableResult
    static func tap(_ app: XCUIApplication, _ label: String, settleSeconds: TimeInterval = 1.2) -> Bool {
        guard let element = find(app, label), element.isHittable else { return false }
        element.tap(); settle(settleSeconds); return true
    }

    /// Tap `label`, then wait up to `timeout` for something labelled exactly `expect` to appear, so
    /// the capture never races the presentation.
    @discardableResult
    static func tapExpecting(_ app: XCUIApplication, _ label: String, expect: String,
                             timeout: TimeInterval = 4) -> Bool {
        guard let element = find(app, label), element.isHittable else { return false }
        element.tap()
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if findExact(app, expect) != nil { settle(0.8); return true }
            settle(0.3)
        }
        return false
    }

    /// Tap `label`, then wait for the screen titled `title` (a pushed page or a presented sheet).
    /// A row and the page it opens often share a name, so the title is looked for in the bar.
    @discardableResult
    static func tapExpectingScreen(_ app: XCUIApplication, _ label: String, title: String,
                                   timeout: TimeInterval = 4) -> Bool {
        guard let element = find(app, label), element.isHittable else { return false }
        element.tap()
        guard app.navigationBars[title].waitForExistence(timeout: timeout) else { return false }
        settle(0.8)
        return true
    }

    /// Tap `label`, then wait for a system alert / confirmation dialog to present.
    @discardableResult
    static func tapForAlert(_ app: XCUIApplication, _ label: String, timeout: TimeInterval = 4) -> Bool {
        guard let element = find(app, label), element.isHittable else { return false }
        element.tap()
        return app.alerts.firstMatch.waitForExistence(timeout: timeout)
            || app.sheets.firstMatch.waitForExistence(timeout: 1)
    }

    /// Type into the screen's search field. False when there is none to type into.
    @discardableResult
    static func search(_ app: XCUIApplication, _ text: String) -> Bool {
        let field = app.searchFields.firstMatch
        guard field.waitForExistence(timeout: 4), field.isHittable else { return false }
        field.tap()
        field.typeText(text)
        settle(1.0)
        return true
    }
}
