# iOS Phase 2 — Home Dashboard Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Replace the Live tab's "widgets stacked in a scroll" (`LiveDashboardView`) with the Android-v2 Home dashboard — large title, status-first "Your widgets" strip, Connections / Every-day / Look groups, version footer — on the Phase-1 design system, plus a cross-widget health model that orders problems first.

**Architecture:** New pure model code (`WidgetHealth`, configured-widget inventory, connection status) in HearthKit (macOS-testable, no UIKit). New SwiftUI views in the app target (`Hearth/Home/`). The 3-tab `TabView` in `ContentView` and ALL its deep-link/sheet/gate/`onOpenURL` infrastructure stay intact — only the Live tab's body changes from `LiveDashboardView` to `HomeView`. The full collapse of the tab shell into NavigationStack is deferred to a later phase (needs Settings/widget push destinations from Phases 3–4).

**Tech Stack:** SwiftUI, Swift 6, iOS 17+, Swift Testing, XcodeGen, HearthKit.

**Spec:** `docs/superpowers/specs/2026-11-26-ios-android-parity-port-design.md` (Phase 2); target mocks `hearth-task-artifacts/hearth-settings/final-v2/00-home-first-run.png`, `01-home.png`, `02-home-needs-sign-in.png`, `02c-home-offline.png`, `03-home-dark.png`.

## Global Constraints

- iOS 17; iPhone-only. Swift Testing only; HearthKit tests `cd HearthKit && swift test` (macOS — no UIColor/UITraitCollection in model code).
- `xcodegen generate` output stays in sync with tracked files (CI `git diff --exit-code`). Commit regenerated files in sync.
- All styling via the Phase-1 design system (`HearthColor`/`HearthFont`/`HearthMetrics`/`StatusPill`/`IconTile`/`HearthSwitch`/`HearthGroup`/`HearthRow`); no ad-hoc colors/sizes.
- Do NOT remove or restructure the `ContentView` TabView, `.sheet(item: $presentedSheet)`, the gate `.onChange` handlers, `.onOpenURL`, or the settings-return affordances. Phase 2 only swaps the Live tab body.
- "Problems first": the Your-widgets strip and any ordering sorts by `WidgetHealth` severity, highest first.
- Version footer reads the real bundle version/build.

## Review Focus

- **Empty/first-run:** no HA config and no widgets configured → the "Get started" 2-step card shows, not an empty/broken dashboard (Task 7 + Task 8 tests).
- **Dark mode + large text:** HomeView and all rows adapt and reflow (Task 8 preview at `.accessibilityExtraLarge` + dark).
- **A widget with unreadable state:** a snapshot that failed to load maps to `.error`/`.offline` (never silently `.ok`) and sorts to the top (Task 1 tests cover each family's failure → health).
- **Deep-links/sheets still work:** swapping the Live tab body must not break the TabView's `onOpenURL`/gate/sheet funnel (Task 8 keeps them; a smoke check in Task 9).
- **No HA / signed-out ChargePoint:** Connections rows show the correct amber "Needs sign-in" / neutral states, not a crash or blank (Task 3 + Task 6).

---

### Task 1: `WidgetHealth` model + per-family mappers + severity order

**Files:** Create `HearthKit/Sources/HearthKit/Home/WidgetHealth.swift`; Test `HearthKit/Tests/HearthKitTests/WidgetHealthTests.swift`.

**Interfaces — Produces:**
- `public enum WidgetHealth: Int, Sendable, Comparable, CaseIterable { case ok = 0, paused, stale, offline, needsSignIn, setup, error }` with `severity` = raw value and `Comparable` by severity (higher = more urgent). Add `public var sortsFirst: Bool { self != .ok }`.
- `public func widgetHealth(tile: TileSnapshotState, hasError: Bool) -> WidgetHealth` — maps the Tile family: `.failed`→`.error`, `.setup`/`.choose`→`.setup`, `.loading`→`.stale`, `.empty`→`.ok`, `.ready`→`.ok`.
- `public func widgetHealth(stale: Bool, error: Bool, needsSettings: Bool, needsSignIn: Bool) -> WidgetHealth` — maps the Beacon family flags with this precedence: error→`.error`, needsSignIn→`.needsSignIn`, needsSettings→`.setup`, stale→`.stale`, else `.ok`.
- `public func mostUrgent(_ healths: [WidgetHealth]) -> WidgetHealth` (max, or `.ok` if empty).

- [ ] Step 1: failing test `WidgetHealthTests` — assert the ordering (`.error > .ok`, `.needsSignIn > .stale`), each Tile case mapping, each Beacon precedence (error beats needsSignIn beats setup beats stale), and `mostUrgent`.
- [ ] Step 2: run `cd HearthKit && swift test --filter WidgetHealthTests` → FAIL.
- [ ] Step 3: implement. Step 4: test PASS. Step 5: full `swift test` + `xcodegen generate` + `git diff --exit-code` clean. Step 6: commit `feat(ios): WidgetHealth cross-widget status model`.

---

### Task 2: Configured-widget inventory

**Files:** Create `HearthKit/Sources/HearthKit/Home/HomeWidgetInventory.swift`; Test `.../HomeWidgetInventoryTests.swift`.

**Interfaces — Consumes:** `HaConfig` (its selection fields). **Produces:**
- `public enum HomeWidgetKind: String, CaseIterable, Sendable { case car, alarm, thermostat, doors, quick, lights, favourites, activity, battery, chargePoint }` with `displayName`, `icon` (SF Symbol), `hue: TileHue`.
- `public func configuredWidgets(config: HaConfig, chargePointSignedIn: Bool) -> [HomeWidgetKind]` — includes a kind when its selection is present in `HaConfig` (alarm: `isComplete`; thermostat: `hasClimate`; car: `carReady`; doors: `doorsChosen`/`!doorIds.isEmpty`; quick: `!scriptIds.isEmpty`; lights: `!lightPins.isEmpty`; favourites: `!favouriteIds.isEmpty`; activity/battery: `!sensorIds.isEmpty`; chargePoint: `chargePointSignedIn`). Order = `HomeWidgetKind.allCases` order.

- [ ] Steps: failing test (a fully-populated `HaConfig` → all kinds; an empty config → `[]`; partial config → only the configured) → FAIL → implement → PASS → full suite + gate clean → commit `feat(ios): configured-widget inventory`.

---

### Task 3: Connection status model

**Files:** Create `HearthKit/Sources/HearthKit/Home/ConnectionStatus.swift`; Test `.../ConnectionStatusTests.swift`.

**Interfaces — Produces:**
- `public enum HaConnectionStatus { case notSetUp, needsSignIn, connected }` + `public func haConnectionStatus(_ config: HaConfig) -> HaConnectionStatus` (baseUrl blank → notSetUp; `!isSignedIn` → needsSignIn; else connected).
- `public enum CpConnectionStatus { case notSetUp, needsSignIn, connected }` + `public func cpConnectionStatus(signedIn: Bool, hasAccount: Bool) -> CpConnectionStatus`.
- `public extension HaConnectionStatus { var tone: StatusTone; var label: String }` (connected→.ok "Connected"; needsSignIn→.warn "Needs sign-in"; notSetUp→.neutral "Not set up"). Same for `CpConnectionStatus`.

- [ ] Steps: failing test (each config permutation → status + tone/label; verify connected→.ok, needsSignIn→.warn — never swapped) → FAIL → implement → PASS → full suite + gate clean → commit `feat(ios): HA/ChargePoint connection status`.

---

### Task 4: Home header + version footer views

**Files:** Create `Hearth/Home/HomeHeader.swift`, `Hearth/Home/HomeFooter.swift`.

**Interfaces — Produces:** `struct HomeHeader: View` (large "Hearth" title via `HearthFont.largeTitle`, `HearthColor.ink`, leading-aligned, padded per the mock) with an optional signed-in toast slot; `struct HomeFooter: View` (centered version "Hearth X.Y.Z (build)" from `Bundle.main` `CFBundleShortVersionString`/`CFBundleVersion`, `HearthFont.subtitle`/`HearthColor.mute`, and a "Check for updates" affordance that's a no-op stub for now with a `// TODO Phase 6: wire Sparkle/updater` comment — iOS has no Sparkle; leave as inert button).

- [ ] Steps: build the two views with `#Preview` (light+dark). No logic test needed (pure layout); verification is the build + preview + the Task 9 screenshot. Commit `feat(ios): home header + version footer`.
- [ ] Add a tiny testable helper `HearthKit/.../Home/VersionString.swift` `func versionString(short: String, build: String) -> String` ("X.Y.Z (build)") with a Swift Testing test, so the footer's formatting is pinned. (This is the one unit-tested piece of this task.)

---

### Task 5: "Your widgets" strip

**Files:** Create `Hearth/Home/YourWidgetsStrip.swift`.

**Interfaces — Consumes:** Task 1 `WidgetHealth`, Task 2 `HomeWidgetKind`. **Produces:** `struct YourWidgetsStrip: View` taking `let items: [HomeWidgetItem]` where `public struct HomeWidgetItem: Identifiable { id; kind: HomeWidgetKind; stateLine: String; health: WidgetHealth; tapRoute: HomeRoute }` (define `HomeWidgetItem` + `enum HomeRoute` in `HearthKit/.../Home/HomeWidgetItem.swift`, Task 5a). A horizontal scroll of mini cards (`HearthMetrics.miniCardW`=174 wide, `miniCardRadius`=22), each: `IconTile`(kind.icon/hue) + kind.displayName + the live `stateLine` + a `StatusPill` when `health.sortsFirst`, chevron. Plus a trailing "+ Add" card. **Items are pre-sorted problems-first by the caller** (HomeView), but the strip must also provide a static `HomeWidgetItem` sort helper `sortedProblemsFirst([HomeWidgetItem]) -> [HomeWidgetItem]` (stable; by `health` descending then inventory order) — unit-tested.

- [ ] Steps: define `HomeWidgetItem`/`HomeRoute` (5a) + the sort helper with a Swift Testing test (problems sort ahead of ok, stable within equal health) → the view consuming them with a `#Preview` (a mix of ok + warn items, light+dark). Commit `feat(ios): Your-widgets strip`.

---

### Task 6: Connections group

**Files:** Create `Hearth/Home/ConnectionsSection.swift`.

**Interfaces — Consumes:** Task 3. **Produces:** `struct ConnectionsSection: View` taking HA + CP statuses + tap closures. A `HearthGroup("Connections")` with two `HearthRow`s: Home Assistant (`IconTile("house", .blue)`, subtitle = connection label, `subtitleWarn` when needsSignIn, trailing `StatusPill(status.label, tone: status.tone)`, tap → HA route); ChargePoint (`IconTile("bolt.car"/"bolt.fill", .green)`, same pattern, tap → CP route). Rows use the auto-divider from `HearthGroup`.

- [ ] Steps: build the view with `#Preview` covering connected/needsSignIn/notSetUp in light+dark. The status→row mapping logic is already tested in Task 3; this task is view assembly (verify via build + preview + Task 9). Commit `feat(ios): Connections section`.

---

### Task 7: Every-day group, Look row, Get-started card, needs-sign-in banner

**Files:** Create `Hearth/Home/EveryDaySection.swift`, `Hearth/Home/GetStartedCard.swift`, `Hearth/Home/SignInBanner.swift`.

**Interfaces — Produces:**
- `struct EveryDaySection: View` — `HearthGroup("Every day")` with rows Routines / Leave-by / Travel days / Safety alerts, each `IconTile`+title+subtitle+chevron, tap → a `HomeRoute` (these features arrive in Phase 5; for now the route is `.settings` i.e. opens the existing Settings tab, so no dead ends). Plus a `HearthGroup("Look")` single row "Card style" → `.settings`. (Put the Look row here or a tiny `LookSection.swift` — builder's choice.)
- `struct GetStartedCard: View` — the first-run 2-step card ("Connect Home Assistant" / "Add a widget") with step states (done/next), shown until HA connected AND ≥1 widget configured. Tap step → HA route / Add route.
- `struct SignInBanner: View` — a single amber banner shown when a connection needs sign-in (text + fix action), matching `02-home-needs-sign-in.png`.

- [ ] Steps: build the three views with `#Preview`s (light+dark; Get-started in both step states). A small unit-tested helper `func showGetStarted(haConnected: Bool, widgetCount: Int) -> Bool` in HearthKit (`Home/HomeGating.swift`) pins the first-run condition. Commit `feat(ios): every-day/look sections + get-started + sign-in banner`.

---

### Task 8: Assemble `HomeView` and swap it into the Live tab

**Files:** Create `Hearth/Home/HomeView.swift`; Modify `Hearth/HearthApp.swift` (`liveTab` body: `LiveDashboardView` → `HomeView`). Keep `LiveDashboardView.swift` in the tree (unreferenced is fine, or delete if clearly dead — builder's call; if deleted, confirm nothing else references it).

**Interfaces — Consumes:** Tasks 1–7 and the existing snapshot fetchers (`CarLiveSnapshot.fetch`, `AlarmLiveSnapshot.fetch`, `CpLiveSnapshot.fetch`, `ThermostatLiveModel`), `HaConfig`, `CpSessionStore`, `RefreshSignal`.
**Produces:** `struct HomeView: View` (`init(config: HaConfig, onSignOut: @escaping () -> Void)`), a `ScrollView` over `HomeColor.page` background composing: `HomeHeader` → (first-run `GetStartedCard` OR `SignInBanner` when a connection needs sign-in) → `YourWidgetsStrip` (items built by mapping each configured widget's live snapshot → `HomeWidgetItem` with `WidgetHealth`, sorted problems-first) → `ConnectionsSection` → `EveryDaySection`/Look → `HomeFooter`. Reuses the existing fetch/refresh plumbing from `LiveDashboardView` (the `withTaskGroup` fetch, `RefreshSignal` onChange, `.task(id: config)`), now feeding the health/item mapping instead of fixed cards. Tapping a `HomeRoute` uses the EXISTING navigation primitives (HA → Settings tab/reconnect sheet, CP → CP sheet, Add/settings → Settings tab) via closures passed from `ContentView` — do not add a new NavigationStack.

- [ ] Step 1: failing test — a pure `HearthKit` mapping function `func homeWidgetItems(config:, snapshots:) -> [HomeWidgetItem]` that turns the configured widgets + their health into sorted items; test it with fixtures (a configured car that's stale + an ok alarm → car sorts first). Put it in `HearthKit/.../Home/HomeItemsBuilder.swift`.
- [ ] Step 2: run → FAIL. Step 3: implement the builder + `HomeView` assembling all sections and wiring the existing fetchers + route closures; `ContentView.liveTab` passes the route closures (reuse its existing `selection = 1` / sheet presentation code). Step 4: builder test PASS. Step 5: full `cd HearthKit && swift test` + an **app build for simulator** (`xcodebuild -sdk iphonesimulator CODE_SIGNING_ALLOWED=NO build`) must succeed; `xcodegen generate` + `git diff --exit-code` clean. Step 6: commit `feat(ios): Home dashboard replaces Live tab`.
- [ ] Add `#Preview`s of `HomeView` in: signed-in populated (light), dark, first-run, needs-sign-in, and `.accessibilityExtraLarge`.

---

### Task 9: Verify against mocks + deep-link smoke check + parity note

**Files:** none (verification) + `docs/PARITY-AUDIT.md`.

- [ ] Step 1: boot ONE simulator, build+install Debug, launch `HomeView` states (reuse/extend the `-designGallery`-style hook or the DEBUG fixture hosts; if a dedicated `-homePreview` arg is easiest, add it behind `#if DEBUG`). Screenshot populated + first-run + dark to `/tmp/ds-home-*.png`.
- [ ] Step 2: side-by-side the screenshots with `final-v2/01-home.png`, `00-home-first-run.png`, `03-home-dark.png`; note any gaps.
- [ ] Step 3: deep-link smoke check — launch with a `hearth://car-readings/...` URL (or trigger `WidgetRefreshIntent`) and confirm the app still routes (the TabView funnel is intact). Capture the result.
- [ ] Step 4: shut down the sim; update `docs/PARITY-AUDIT.md` ("## Home dashboard (Phase 2)" — components + state coverage + any deferred gap). Commit `chore(ios): Phase 2 home parity note`.

---

## Notes for later phases
- Full nav collapse (fold Settings/Preview tabs into Home push-navigation + re-host `presentedSheet`/gates/`onOpenURL` on a NavigationStack) is deferred until Phase 3/4 provide the Settings and widget-page push destinations. Phase 2 deliberately keeps the TabView.
- Every-day feature rows (Routines/Leave-by/Travel/Safety/Goodnight) currently route to the Settings tab; Phase 5 builds the real destinations.
- Glance is not a live iOS widget; building it is Phase 4.
