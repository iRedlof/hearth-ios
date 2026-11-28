# Render harness

A picture of every screen and every widget of the built app, so the design can be checked for
consistency in one place. It is a DEBUG-only tool: nothing here is compiled into a Release build.

## What it is

| Piece | Where | What it does |
|---|---|---|
| Demo house | `Hearth/DemoHouse/` | Launch argument `-demoHouse`: the real app, signed in to one fictional house, with no backend |
| Walker | `HearthRenderTests/` (target `HearthRenderTests`, scheme `HearthRender`) | XCUITest that launches the app screen by screen and saves PNGs |
| Runner | `scripts/render/run_all.sh` | Builds once, runs the walker one batch at a time on a freshly booted simulator, copies the PNGs out |
| Gallery | `scripts/render/build_gallery.py` | Crops the widget shots, writes `index.html` and `manifest.md`, flags unrendered frames |

### The demo house

`-demoHouse` makes the app behave as signed in to Home Assistant and ChargePoint with healthy,
populated data, so the real `HomeView` and every sheet and page draw as if lived in:

- `DemoHouseURLProtocol` answers every Home Assistant request on `URLSession.shared` (states,
  one entity's state, templates, service calls, the logbook) from `DemoHouseCatalog`.
- `DemoHouseCatalog` is the house: an alarm panel and a front-door lock, a garage door (plus a gate
  and a blind, so the Garage door picker has something to offer and something to leave out), doors
  and a window for Activity and Goodnight, a thermostat with room sensors, lights, scripts,
  favourites, battery sensors, and a car called Stargate. Host `home.example.com`; nothing is real.
- A complete signed-in `HaConfig` is saved, so Home lists every widget as added. The thermostat's
  reading is saved too (`DemoHouseThermostat`), because that widget draws what was last saved.
- `DemoHouseChargePoint` seeds a signed-in ChargePoint account and installs a canned transport
  through `CpSessionStore.demoTransportProvider`.
- Goodnight, Routines (with a learned routine), Morning commute, Leave-by, Travel days and Safety
  alerts are switched on. Card style and the widget names go back to their defaults on every
  launch, so a walk always starts from the same look.

It replaces the stored accounts, so it only runs in the simulator, and the next launch without
`-demoHouse` signs the fictional accounts out again. While they are stored, a process without the
canned transport (the widget extension) gets no ChargePoint runtime, so the made-up session is
never sent to ChargePoint.

### Launch arguments

All DEBUG only. The `-demo…` ones do nothing without `-demoHouse`.

| Argument | Screen |
|---|---|
| `-demoHouse` | Home, every widget added |
| `-demoSessionExpired` | Home with the sign-in banner and paused widgets |
| `-demoHomeAssistant`, `-demoChargePoint` | The two connection pages |
| `-cpShowFasterOffers` | On the ChargePoint page: the Faster Offers sheet |
| `-widgetPage <kind>` | A widget's page (`car`, `alarm`, `thermostat`, `quick`, `lights`, `favourites`, `activity`, `battery`, `chargePoint`) |
| `-widgetShowRename`, `-widgetShowRemove` | On a widget page: the Rename / Remove sheet |
| `-demoPicker <name>` | An entity picker (`alarm`, `lock`, `garage`, `thermostat`, `sensors`, `lights`, `scripts`, `favourites`) |
| `-demoPickerSearch <text>` | In a picker: the search already typed |
| `-cardStyle`, `-cardStyle <kind>` | Card style for All cards, or for one widget |
| `-demoCardStyle <value>` | The Card style the launch starts in, e.g. `colour:ocean` or `black,text=larger` (the `-parityCardStyle` syntax, see `CARD-STYLE-IOS.md`) |
| `-addGallery`, `-goodnight`, `-routines`, `-leaveBy`, `-travelDays`, `-safetyAlerts`, `-morningCommute`, `-houseConfirm` | Those pages |
| `-demoThermostatDetail` | Thermostat controls |
| `-renderColorScheme light\|dark` | Draws the app in that appearance |
| `-renderSignedOut` | Without `-demoHouse`: the fresh sign-in screen (signs the stored accounts out; simulator only) |

Widgets are drawn by the parity screen, without the demo house: `-parityState <id>` with
`-parityWidth`, `-parityHeight`, `-parityCardStyle`, plus two DEBUG-only additions for the walker:
`-parityFlush` pins the card to the top-left corner on its magenta key so the crop is a fixed
rect, and `-parityList` shows the catalog's ids for the walker to read.

### What gets rendered

`HearthRenderTests` draws the screens, light and dark unless noted:

| Method | Launches | Screens |
|---|---|---|
| `test01Launch` | 3 | Sign-in; first-run Home |
| `test02Home` | 4 | Home (⋯ menu, Your widgets strip, full scroll); Home with an expired session |
| `test03HomeAssistant` | 8 | Home Assistant page (Web address, Sign-in, sign-out alert); needs sign-in; Garage door picker, with and without a search |
| `test04Pickers` | 8 | The other pickers; a search that matches nothing (light) |
| `test05ChargePoint` | 10 | ChargePoint page and sign-out alert; Faster Offers; Alerts; not set up; Morning commute |
| `test06Look` | 10 | Add a widget; Card style: Status, Colour with its swatches, Black, Larger text, one widget's own |
| `test07WidgetPagesLight`, `test08WidgetPagesDark` | 9 each | Every widget page |
| `test09WidgetSheets` | 5 | Rename and Remove sheets; the Garage door picker reached from the Alarm page, and its search field typed into |
| `test10EveryDayA` | 6 | Goodnight key and its editors; Routines and its turn-off confirmation; Leave-by |
| `test11EveryDayB` | 6 | Travel days; Safety alerts; House confirm |
| `test12Detail` | 4 | Thermostat controls; Car readings |
| `test13DesignGallery` | 2 | Design system gallery |
| `test14LargeTextA`, `test15LargeTextB` | 8, 7 | The top of each main screen at the largest accessibility text size (light) |
| `test16CalendarDenied` | 2 | Leave-by without calendar access |

`WidgetRenderTests` draws every widget fixture in `ParityCatalog` (the `readable` layout proofs
excluded), each twice in light: 364×170 in the default Card style, and 329×155 with Larger
text. `test00Index` asks the app for the ids (`-parityList`); `testBatch00` … `testBatch59` render
five ids each (10 launches).

`WidgetPlacementTests` places a widget on the simulator's Home Screen for a look at the real
WidgetKit drawing. It is not a render and the runner skips it; run it from Xcode when wanted.

A screen the walker cannot reach is not a failure: it is written to the catalog as a gap and listed
under **Gaps** in `manifest.md`.

## How to run it

Use a simulator kept for this: the demo house replaces the app's stored accounts on it. Best
without Hearth widgets on its Home Screen (a placed widget would ask `home.example.com` for its
data). Needs `xcodegen` and Python 3 with Pillow.

```bash
scripts/render/run_all.sh <simulator-udid> <derived-data-dir>
```

It regenerates the project, runs `build-for-testing` once, then for each batch (one test method):
shuts the simulator down and boots it, runs that method with
`xcodebuild test-without-building -only-testing:…`, and copies the new PNGs out of the test
runner's `Documents/renders`. At the end it runs `build_gallery.py`.

Output, under `<derived-data-dir>/render-output` (or `RENDER_OUT`):

- `gallery/index.html`: everything, light and dark side by side, then the widgets
- `gallery/manifest.md`: what each image is and how it was reached, the gaps, the suspect frames
- `gallery/screens/`, `gallery/widgets/`: the images (widgets cropped to the card)
- `raw/`: the walker's full-screen PNGs and `catalog.tsv`. `logs/`: one xcodebuild log per batch

| Variable | Default | Meaning |
|---|---|---|
| `RENDER_OUT` | `<derived-data-dir>/render-output` | Output folder |
| `RENDER_ONLY` | everything | Only the batches whose `Class/method` matches this regex, e.g. `HearthRenderTests/test06` or `WidgetRenderTests` |
| `RENDER_WATCHDOG_SECONDS` | `600` | A batch running longer is killed |
| `RENDER_RETRIES` | `1` | How many times a failed batch is run again |
| `RENDER_XCODEBUILD_ARGS` | none | Extra xcodebuild arguments |

`raw/` is kept between runs, so a re-run with `RENDER_ONLY` replaces just those images and the
gallery is rebuilt from all of them. Delete the output folder for a clean render.

### Why batches

The simulator's renderer goes black after roughly 20 app launches without a reboot. So:

- A test method launches the app at most 12 times (`Render.maxLaunchesPerTest`), not counting
  the throwaway launch below; `Render.launch` fails the test when a method goes over.
- The runner reboots the simulator before every batch.
- The first launch after a boot often fails ("did not return a process handle"), so every test
  starts with a throwaway launch whose failure is expected (`Render.beginTest`).
- `build_gallery.py` lists black frames, and widget shots without their magenta key, under
  **Suspect frames**. Run those batches again with `RENDER_ONLY`.

### By hand

One batch from the command line, on a booted simulator:

```bash
xcodegen generate
xcodebuild test -project Hearth.xcodeproj -scheme HearthRender -destination "id=<udid>" \
  -skipMacroValidation -only-testing:HearthRenderTests/HearthRenderTests/test06Look
python3 -I scripts/render/build_gallery.py \
  --src "$(xcrun simctl get_app_container <udid> com.rohit.hearth.rendertests.xctrunner data)/Documents/renders" \
  --out /tmp/hearth-gallery
```

Or open a screen yourself: run the Hearth scheme in the simulator with the launch arguments above.

## How to add a screen

1. **Make it reachable.** Prefer a launch argument over taps: it is deterministic. Many screens
   already have one (`handleDebugLaunchArgs` in `HearthApp.swift`). A new one goes there, inside
   `#if DEBUG`, and reads the demo house's data. If the screen needs data the house lacks, add the
   entity to `DemoHouseCatalog` (and to `DemoHouseCatalog.config` if it must be selected).
2. **Capture it.** In `HearthRenderTests.swift`, add a line to the method for its area:

   ```swift
   page("08-newpage", ["-newPage"], a, group: "08 Every day", shows: "New page")   // scrolls and captures
   screen("08-newsheet", ["-newSheet"], a, group: "08 Every day", shows: "New sheet")   // one capture
   ```

   For a state reached by tapping, pass `page` a closure and use `Render.tap`,
   `Render.tapExpectingScreen`, `Render.tapForAlert` and `Render.search`; record a `Render.gap`
   when the control is not there. The file name's number prefix decides where the image sorts.
3. **Mind the launch budget.** Update the launch count in the method's comment. If it passes 12,
   move the new screens into a new numbered method: the runner finds methods by name, there is no
   list to update. Put `CalendarDenied` in the name of a method that needs calendar access revoked.
4. **A new widget state** needs nothing here: add it to `ParityCatalog` and `WidgetRenderTests`
   picks it up. If the catalog outgrows the batch methods, `test00Index` fails and says so.

Then run just that batch: `RENDER_ONLY='HearthRenderTests/test10' scripts/render/run_all.sh …`.

## Not in Release

- Every app-side line is inside `#if DEBUG`: `Hearth/DemoHouse/*` whole files, and the hooks in
  `HearthApp.swift`, `WidgetPage.swift`, `ChargePointPage.swift`, the two pickers,
  `Shared/ParityCatalog.swift` and `Shared/CpSessionStore.swift`. The Release branch of each is the
  code that was there before.
- `HearthRenderTests` is a separate UI-test target. The `Hearth` scheme, which the release
  workflows archive, builds only the app and its dependencies.
- To check a build: `strings` and `nm` on the Release `Hearth` and `HearthWidgets` binaries find
  no `DemoHouse`, `demoPicker`, `parityFlush` or `renderColorScheme`.
