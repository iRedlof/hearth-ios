import XCTest

/// The Hearth render walker (docs/RENDER-HARNESS.md). Each test method is one batch: it launches the
/// real app (`-demoHouse`) with per-screen arguments, drives the real UI and captures what it sees.
///
/// The simulator's renderer goes black after roughly 20 app launches, so a batch launches the app at
/// most `Render.maxLaunchesPerTest` times and `scripts/render/run_all.sh` reboots the simulator
/// between batches. The launch count is in each method's comment; `Render.launch` fails the test
/// when a method goes over. Methods are numbered so they run in the documented order.
///
/// All interactions are existence-guarded: a missing control logs a GAP to the catalog instead of
/// aborting the walk.
@MainActor
final class HearthRenderTests: XCTestCase {
    override func setUp() async throws {
        continueAfterFailure = true
        Render.beginTest()
    }

    private let both: [Render.Appearance] = [.light, .dark]
    private let demo = "demo house"

    /// One launch: `args` over the demo house, captured from top to bottom.
    private func page(_ base: String, _ args: [String], _ appearance: Render.Appearance, group: String,
                      shows: String, source: String? = nil, demoHouse: Bool = true,
                      then interact: ((XCUIApplication) -> Void)? = nil) {
        let app = Render.launch(args, appearance: appearance, demoHouse: demoHouse)
        Render.captureScroll(Render.scrollView(app), base: base, appearance: appearance, group: group,
            reached: "launch " + ((demoHouse ? ["-demoHouse"] : []) + args).joined(separator: " "),
            shows: shows, source: source ?? demo)
        interact?(app)
        app.terminate()
    }

    /// One launch: `args` over the demo house, one capture (a sheet, or a screen that fits).
    private func screen(_ name: String, _ args: [String], _ appearance: Render.Appearance, group: String,
                        shows: String, source: String? = nil, demoHouse: Bool = true) {
        let app = Render.launch(args, appearance: appearance, demoHouse: demoHouse)
        Render.shot("\(name)-\(appearance.rawValue)", group: group,
            reached: "launch " + ((demoHouse ? ["-demoHouse"] : []) + args).joined(separator: " "),
            shows: shows, source: source ?? demo)
        app.terminate()
    }

    // MARK: 01 — Launch & first run (3 launches)
    func test01Launch() {
        let group = "01 Launch & first run"
        // The sign-in screen draws dark whatever the system appearance, so it is captured once.
        screen("01-signin-0", ["-renderSignedOut"], .dark, group: group,
               shows: "Home Assistant sign-in, fresh install (always dark)", source: "empty store",
               demoHouse: false)
        for a in both {
            page("01-firstrun", ["-homePreviewFirstRun"], a, group: group,
                 shows: "First-run Home with the Get started card", source: "fixture (empty HaConfig)",
                 demoHouse: false)
        }
    }

    // MARK: 02 — Home (4 launches)
    func test02Home() {
        let group = "02 Home"
        for a in both {
            let app = Render.launch([], appearance: a)
            // The ⋯ menu and the strip are above the fold: use them before scrolling.
            if Render.tapExpecting(app, "More actions", expect: "Sign out") {
                Render.shot("02-home-menu-\(a.rawValue)", group: group, reached: "Home → ⋯ (More actions)",
                            shows: "Header menu open (Refresh, Sign out)", source: demo)
                app.tap()   // dismisses the menu
                Render.settle(0.6)
            } else { Render.gap("02-home-menu-\(a.rawValue)", group: group, reason: "⋯ menu did not open") }
            // "Your widgets": every added widget, then the Add card at the end of the strip.
            let strip = app.scrollViews.element(boundBy: 1)
            if strip.exists {
                for _ in 0..<3 { strip.swipeLeft(velocity: .slow) }
                Render.settle(0.8)
                Render.shot("02-home-strip-\(a.rawValue)", group: group, reached: "Home → swipe Your widgets left",
                            shows: "Your widgets scrolled to the end (Add card)", source: demo)
                for _ in 0..<3 { strip.swipeRight(velocity: .slow) }
                Render.settle(0.6)
            } else { Render.gap("02-home-strip-\(a.rawValue)", group: group, reason: "Your widgets strip not found") }
            Render.captureScroll(Render.scrollView(app), base: "02-home", appearance: a, group: group,
                reached: "launch -demoHouse", shows: "Home with every widget added, full scroll", source: demo)
            app.terminate()
        }
        for a in both {
            page("02-home-expired", ["-demoSessionExpired"], a, group: group,
                 shows: "Home with the Home Assistant sign-in banner and paused widgets",
                 source: "demo house (refresh token dropped)")
        }
    }

    // MARK: 03 — Home Assistant page, Garage door picker (8 launches)
    func test03HomeAssistant() {
        let group = "03 Home Assistant"
        for a in both {
            let app = Render.launch(["-demoHomeAssistant"], appearance: a)
            // Connection rows first (top of the page), then the full scroll.
            if Render.tapExpectingScreen(app, "Web address", title: "Web address") {
                Render.shot("03-ha-address-\(a.rawValue)", group: group, reached: "Home Assistant → Web address",
                            shows: "Web address sheet", source: demo)
                Render.tap(app, "Cancel")
            } else { Render.gap("03-ha-address-\(a.rawValue)", group: group, reason: "Web address sheet did not present") }
            if Render.tapExpecting(app, "Sign-in", expect: "About Sign-in") {
                Render.shot("03-ha-signin-\(a.rawValue)", group: group, reached: "Home Assistant → Sign-in",
                            shows: "Sign-in explainer sheet", source: demo)
                if Render.tapForAlert(app, "Sign out") {
                    Render.shot("03-ha-signout-\(a.rawValue)", group: group,
                                reached: "Home Assistant → Sign-in → Sign out",
                                shows: "Sign out of Home Assistant? alert", source: demo)
                    Render.tap(app, "Cancel")
                } else { Render.gap("03-ha-signout-\(a.rawValue)", group: group, reason: "sign-out alert did not present") }
                Render.tap(app, "Done")
            } else { Render.gap("03-ha-signin-\(a.rawValue)", group: group, reason: "Sign-in explainer did not present") }
            Render.captureScroll(Render.scrollView(app), base: "03-ha", appearance: a, group: group,
                reached: "launch -demoHouse -demoHomeAssistant", shows: "Home Assistant page, connected", source: demo)
            app.terminate()

            screen("03-ha-needssignin", ["-haPageNeedsSignIn"], a, group: group,
                   shows: "Home Assistant page, needs sign-in", source: "fixture (mock runtime)", demoHouse: false)
            screen("03-picker-garage", ["-demoPicker", "garage"], a, group: group,
                   shows: "Garage door picker: garage and gate offered, the blind left out, search field")
            screen("03-picker-garage-search", ["-demoPicker", "garage", "-demoPickerSearch", "gate"], a, group: group,
                   shows: "Garage door picker, searching \"gate\"")
        }
    }

    // MARK: 04 — Entity pickers (8 launches, light)
    func test04Pickers() {
        let group = "04 Pickers"
        let pickers = [("alarm", "Alarm panel picker"), ("lock", "Front door picker (None offered)"),
                       ("thermostat", "Thermostat picker"), ("sensors", "Room sensors picker (multiple)"),
                       ("lights", "Always show picker (lights, multiple)"),
                       ("scripts", "Scripts picker (up to 6)"), ("favourites", "Tiles picker (up to 12)")]
        for (name, shows) in pickers {
            screen("04-picker-\(name)", ["-demoPicker", name], .light, group: group, shows: shows)
        }
        screen("04-picker-favourites-nomatch", ["-demoPicker", "favourites", "-demoPickerSearch", "zzz"], .light,
               group: group, shows: "Tiles picker, a search that matches nothing")
    }

    // MARK: 05 — ChargePoint (10 launches)
    func test05ChargePoint() {
        let group = "05 ChargePoint"
        for a in both {
            page("05-cp", ["-demoChargePoint"], a, group: group, shows: "ChargePoint page, connected") { app in
                // Sign out sits at the bottom, where the scroll capture ended.
                if Render.tapForAlert(app, "Sign out") {
                    Render.shot("05-cp-signout-\(a.rawValue)", group: group, reached: "ChargePoint → Sign out",
                                shows: "Sign out of ChargePoint? alert", source: self.demo)
                    Render.tap(app, "Cancel")
                } else { Render.gap("05-cp-signout-\(a.rawValue)", group: group, reason: "sign-out alert did not present") }
            }
            screen("05-cp-fasteroffers", ["-demoChargePoint", "-cpShowFasterOffers"], a, group: group,
                   shows: "Faster Offers sheet")
            page("05-cp-alerts", ["-cpAlerts"], a, group: group, shows: "ChargePoint alerts page",
                 source: "fixture (mock runtime)", demoHouse: false)
            screen("05-cp-notsetup", ["-cpPageNotSetUp"], a, group: group, shows: "ChargePoint page, not set up",
                   source: "fixture (mock runtime)", demoHouse: false)
            page("05-cp-morningcommute", ["-morningCommute"], a, group: group, shows: "Morning Commute page")
        }
    }

    // MARK: 06 — Add a widget, Card style (10 launches)
    func test06Look() {
        let group = "06 Look"
        for a in both {
            page("06-addgallery", ["-addGallery"], a, group: group, shows: "Add a widget gallery")
            page("06-cardstyle", ["-cardStyle"], a, group: group, shows: "Card style (All cards), Status") { app in
                // The real controls, from the top: Colour shows the eight swatches.
                Render.scrollToTop(Render.scrollView(app))
                let steps = [("Colour", "colour", "Background: Colour, with the colour swatches"),
                             ("Plum", "colour-plum", "Background: Colour, Plum picked"),
                             ("Black", "black", "Background: Black"),
                             ("Larger", "text-larger", "Text size: Larger")]
                for (label, slug, shows) in steps {
                    if Render.tap(app, label) {
                        Render.shot("06-cardstyle-tap-\(slug)-\(a.rawValue)", group: group,
                                    reached: "Card style → \(label)", shows: shows, source: self.demo)
                    } else {
                        Render.gap("06-cardstyle-tap-\(slug)-\(a.rawValue)", group: group, reason: "\(label) not hittable")
                    }
                }
            }
            page("06-cardstyle-colour", ["-cardStyle", "-demoCardStyle", "colour:ocean"], a, group: group,
                 shows: "Card style (All cards), Colour: swatches, Ocean picked")
            page("06-cardstyle-black-larger", ["-cardStyle", "-demoCardStyle", "black,text=larger,small=off"], a,
                 group: group, shows: "Card style (All cards), Black, Larger text, small print off")
            page("06-cardstyle-own", ["-cardStyle", "alarm"], a, group: group,
                 shows: "Card style for one widget (This card uses)")
        }
    }

    // MARK: 07 / 08 — Widget pages (9 launches each)
    private static let widgetKinds = ["car", "alarm", "thermostat", "quick", "lights", "favourites",
                                      "activity", "battery", "chargePoint"]

    private func widgetPages(_ appearance: Render.Appearance) {
        for kind in Self.widgetKinds {
            page("07-widget-\(kind.lowercased())", ["-widgetPage", kind], appearance, group: "07 Widget pages",
                 shows: "Widget page: \(kind)")
        }
    }

    func test07WidgetPagesLight() { widgetPages(.light) }
    func test08WidgetPagesDark() { widgetPages(.dark) }

    // MARK: 09 — Widget page sheets and the picker reached from a page (5 launches)
    func test09WidgetSheets() {
        let group = "07 Widget pages"
        for a in both {
            screen("07-widget-alarm-rename", ["-widgetPage", "alarm", "-widgetShowRename"], a, group: group,
                   shows: "Rename sheet")
            screen("07-widget-alarm-remove", ["-widgetPage", "alarm", "-widgetShowRemove"], a, group: group,
                   shows: "Remove from home screen sheet")
        }
        // The real path: Alarm page → Garage door → search.
        let app = Render.launch(["-widgetPage", "alarm"], appearance: .light)
        if Render.tapExpectingScreen(app, "Garage door", title: "Garage door") {
            Render.shot("07-widget-alarm-garage-light", group: group, reached: "Alarm page → Garage door",
                        shows: "Garage door picker pushed from the Alarm page", source: demo)
            if Render.search(app, "gar") {
                Render.shot("07-widget-alarm-garage-search-light", group: group,
                            reached: "Alarm page → Garage door → type \"gar\"",
                            shows: "Garage door picker, search typed", source: demo)
            } else { Render.gap("07-widget-alarm-garage-search-light", group: group, reason: "search field not hittable") }
        } else { Render.gap("07-widget-alarm-garage-light", group: group, reason: "Garage door row did not open its picker") }
        app.terminate()
    }

    // MARK: 10 — Every day: Goodnight, Routines, Leave-by (6 launches)
    func test10EveryDayA() {
        let group = "08 Every day"
        for a in both {
            page("08-goodnight", ["-goodnight"], a, group: group, shows: "Goodnight key page (configured)") { app in
                guard a == .light else { return }
                Render.scrollToTop(Render.scrollView(app))
                for (row, title, slug) in [("Hours", "Hours", "hours"), ("Arm mode", "Arm mode", "armmode"),
                                           ("Keep on", "Keep on at night", "keepon")] {
                    if Render.tapExpectingScreen(app, row, title: title) {
                        Render.shot("08-goodnight-\(slug)-light", group: group, reached: "Goodnight key → \(row)",
                                    shows: "Goodnight \(row) editor", source: self.demo)
                        if !Render.tap(app, "Cancel") { Render.tap(app, "Save") }
                    } else {
                        Render.gap("08-goodnight-\(slug)-light", group: group, reason: "\(row) editor did not present")
                    }
                }
            }
            page("08-routines", ["-routines"], a, group: group, shows: "Routines, one learned",
                 source: "demo house (seeded history)") { app in
                guard a == .light else { return }
                Render.scrollToTop(Render.scrollView(app))
                let learn = app.switches.firstMatch
                guard learn.exists, learn.isHittable else {
                    Render.gap("08-routines-turnoff-light", group: group, reason: "Learn my routines switch not found")
                    return
                }
                learn.tap()
                if app.buttons["Turn off"].waitForExistence(timeout: 4) {
                    Render.settle(0.6)
                    Render.shot("08-routines-turnoff-light", group: group, reached: "Routines → Learn my routines off",
                                shows: "Turn-off confirmation", source: self.demo)
                    if Render.tap(app, "Turn off") {
                        Render.shot("08-routines-off-light", group: group, reached: "Routines → confirm Turn off",
                                    shows: "Routines, off", source: self.demo)
                    }
                } else { Render.gap("08-routines-turnoff-light", group: group, reason: "turn-off confirmation did not present") }
            }
            screen("08-leaveby", ["-leaveBy"], a, group: group, shows: "Leave-by times (bottom sheet)")
        }
    }

    // MARK: 11 — Every day: Travel days, Safety alerts, House confirm (6 launches)
    func test11EveryDayB() {
        let group = "08 Every day"
        for a in both {
            screen("08-traveldays", ["-travelDays"], a, group: group, shows: "Travel days (bottom sheet)")
            page("08-safetyalerts", ["-safetyAlerts"], a, group: group, shows: "Safety alerts page")
            screen("08-houseconfirm", ["-houseConfirm"], a, group: group, shows: "House confirm sheet",
                   source: "fixture (sample actions)")
        }
    }

    // MARK: 12 — Detail screens (4 launches)
    func test12Detail() {
        let group = "09 Detail"
        for a in both {
            page("09-thermostat", ["-demoThermostatDetail"], a, group: group, shows: "Thermostat controls")
            page("09-car", ["-carRouteFixture", "normal"], a, group: group, shows: "Car readings, populated",
                 source: "fixture (seeded ticket)", demoHouse: false)
        }
    }

    // MARK: 13 — Design system gallery (2 launches)
    func test13DesignGallery() {
        for a in both {
            page("10-designgallery", ["-designGallery"], a, group: "10 Design gallery",
                 shows: "Design system gallery", source: "fixture (design tokens)", demoHouse: false)
        }
    }

    // MARK: 14 / 15 — Large text (AX XXXL, light), top of each primary screen (8 + 7 launches)
    private func largeText(_ screens: [(String, [String], Bool)]) {
        for (slug, args, demoHouse) in screens {
            screen("11-xxxl-\(slug)", args, .xxxl, group: "11 Large text",
                   shows: "Largest accessibility text, top of \(slug)",
                   source: demoHouse ? demo : "fixture", demoHouse: demoHouse)
        }
    }

    func test14LargeTextA() {
        largeText([("home", [], true), ("ha", ["-demoHomeAssistant"], true), ("cp", ["-demoChargePoint"], true),
                   ("goodnight", ["-goodnight"], true), ("routines", ["-routines"], true),
                   ("leaveby", ["-leaveBy"], true), ("traveldays", ["-travelDays"], true),
                   ("safetyalerts", ["-safetyAlerts"], true)])
    }

    func test15LargeTextB() {
        largeText([("widget-alarm", ["-widgetPage", "alarm"], true), ("widget-car", ["-widgetPage", "car"], true),
                   ("widget-lights", ["-widgetPage", "lights"], true), ("addgallery", ["-addGallery"], true),
                   ("cardstyle", ["-cardStyle"], true), ("picker-garage", ["-demoPicker", "garage"], true),
                   ("designgallery", ["-designGallery"], false)])
    }

    // MARK: 16 — Leave-by without calendar access (2 launches)
    /// Needs calendar access revoked on the host first
    /// (`xcrun simctl privacy <udid> revoke calendar com.rohit.hearth`); `run_all.sh` does that for any
    /// method with `CalendarDenied` in its name, and resets it afterwards.
    func test16CalendarDenied() {
        for a in both {
            screen("08-leaveby-caldenied", ["-leaveBy"], a, group: "08 Every day",
                   shows: "Leave-by with the \"Needs calendar access\" banner",
                   source: "demo house (calendar denied)")
        }
    }
}
