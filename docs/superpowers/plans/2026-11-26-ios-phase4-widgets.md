# iOS Phase 4 — Widgets (Add gallery · widget pages · Card style · Glance) Implementation Plan

> **Update 2026-11-27 (owner decision):** the Glance widget and the small widget sizes were removed
> from the app. What this document says about Glance is kept as a record of the original plan.

> **Update 2026-11-28 (owner decision):** the Doors widget was removed; the garage is a row on the
> Alarm card. What this document says about Doors is kept as a record of the original plan.

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development. Steps use checkbox (`- [ ]`).

**Goal:** Bring the widget experience to Android v2: a re-skinned **Add-a-widget gallery** (categorised, with Added/Needs-HA chips), a **per-widget settings page** template (preview mat + Uses/Safety/Shows/Every day/Look/Remove), a **Card-style** page (the iOS-portable subset), and a **new Glance widget** (the at-a-glance summary) for 11-tile parity — all on the Phase-1 design system.

**Architecture:** Net-new pure/model code in HearthKit (`Glance/` summary+layout ported from Android `HomeGlanceState.kt`/`HomeGlanceLayout.kt`; `CardStyle` model + App-Group store). New views in the app/widget targets. Reuse the existing `WidgetPreviewKind` catalog + `widget(for:)` specimen switch, the `HaConfig` pickers, `WidgetHealth`, `BeaconFreshness`, `ConnectionHero`, and the design system. TabView/deep-link infra kept intact (as prior phases).

**Tech Stack:** SwiftUI, WidgetKit, Swift 6, iOS 17+, Swift Testing, XcodeGen, HearthKit.

**Spec:** design doc Phase 4; mocks `final-v2/` 04/04b/04c (gallery), 11/11b/11c/11d/12/13/13b/15/16/16d (widget pages), 17/18 (card style), Glance card in 04. Android source `/.codex/worktrees/hearth-release-main/app/.../HomeGlance*.kt`.

## Global Constraints
- iOS 17; iPhone-only. Swift Testing only; HearthKit tests on macOS (no UIColor in model code). App/widget build for simulator must pass (`xcodebuild -sdk iphonesimulator CODE_SIGNING_ALLOWED=NO`).
- `xcodegen generate` in sync (CI `git diff --exit-code`). Design tokens for colours/fonts; spacing-literal extraction stays Phase 6.
- Keep the TabView + deep-link/sheet/gate/onOpenURL funnel. Reuse existing snapshot fetchers, `HaConfig`/`HaConfigStore`, `WidgetPreviewKind`, pickers — no new write paths for existing settings.
- **Ruling (Card style):** ship only the iOS-portable axes per `docs/CARD-STYLE-IOS.md` — Background (By state / Colour / Black), Text size, Small-print. OMIT Corners / Glass / Wallpaper (WidgetKit controls container shape+background on a live widget; they can't change it). The page must not present controls that do nothing on a real widget; note the divergence from mocks 17/18 in the parity note.
- **Ruling (Glance):** port the Android `glanceSummary` honestly — Glance summarises only what placed widgets last read (no new network); unreadable saved state → an error feed (never a false "OK"). Refresh is driven by each widget's own timeline writing its feed (no WorkManager analog).

## Review Focus
- **Glance never lies:** a stale/unreadable feed must yield `.cantCheck`/error, never `.ok` (Task 1 tests).
- **"Added" vs "Needs HA" chips:** the gallery reflects real configured/connected state, not hardcoded (Task 4).
- **Card style can't fake live-widget changes:** the page only exposes portable axes; applying them actually affects the widget content (text size/small-print/bg) — not a no-op (Task 7).
- **Per-widget page not-set-up state:** shows "Example · yours appears after setup" + a setup card, not a broken page (Task 5).
- **Glance widget honesty offline/empty:** empty (no widgets/feeds) → "Set up"; signed-out → honest support line (Task 3).

---

### Task 1: Glance summary model (port)
**Files:** Create `HearthKit/Sources/HearthKit/Glance/GlanceSummary.swift`; Test `GlanceSummaryTests.swift`.
Port from Android `HomeGlanceState.kt`: `public struct GlanceFeed { kind: HomeWidgetKind; checkedAt: Date?; error: Bool; items: [GlanceItem]; calm: Bool }`, `public enum GlanceSeverity: Int, Comparable { calm, warn, act, alert, alarm }`, `public enum GlanceVerdict { ok, needYou, alarm, cantCheck, empty }`, `public struct GlanceSummary { verdict; word; tone: StatusTone; lines: [String]; support: String; calmLine: String? }`, and the pure `public func glanceSummary(_ feeds: [GlanceFeed], now: Date, freshMs: Int = 20*60*1000) -> GlanceSummary`. Severity ranking, the "empty→Set up", "error/stale→cantCheck", "any act/alert→needYou/alarm", "all calm→ok" rules, and the support qualifier ("Checked 9:41" / "Last known · 9:12" / "Signed out") exactly as Android.
- [ ] Failing tests covering each verdict (ok/needYou/alarm/cantCheck/empty), the never-false-OK rule (an error feed forces cantCheck), freshness (stale feed → last-known), and severity ordering → FAIL → implement → PASS → full suite + gate clean → commit `feat(ios): Glance summary model`.

### Task 2: Glance feed store + layout
**Files:** Create `HearthKit/Sources/HearthKit/Glance/GlanceLayout.swift` (port `glanceLayout`), `Shared/GlanceFeedStore.swift` (App-Group JSON persistence `glanceFeedsToJson`/`fromJson`); Tests for both.
- `glanceLayout(summary:size:) -> GlanceLayoutPlan` — pure text-measured 2x1 vs 2x2 decision, word-never-shortened, key placement, small-print footer (port the Android rules; make the measuring injectable/deterministic for tests).
- `GlanceFeedStore`: `save(_ feed: GlanceFeed)` / `load() -> [GlanceFeed]` into `group.com.rohit.hearth` as one JSON; unreadable → treated as error feed by the model.
- [ ] Failing tests (layout picks 2x2 when content needs it; feed round-trips JSON; corrupt JSON → error feed) → FAIL → implement → PASS → suite + gate → commit `feat(ios): Glance feed store + layout`.

### Task 3: Glance widget + registration + provider feeds
**Files:** Create `HearthWidgets/GlanceWidget.swift` + `Shared/GlanceView.swift`; Modify `HearthWidgets/HearthWidgetBundle.swift` (register `GlanceWidget`), `HearthKit/.../WidgetPreviewCatalog.swift` (+`.glance` case), `HearthKit/.../Home/HomeWidgetInventory.swift` (+`.glance` HomeWidgetKind), and each provider's timeline to write its `GlanceFeed` to the store.
- `GlanceWidget`: `StaticConfiguration`, kind `com.rohit.hearth.glance`, `[.systemSmall]`, reads feeds via `GlanceFeedStore` + `glanceSummary` + `glanceLayout`, renders `GlanceView` (purple/tone surface, verdict word, lines, support, optional safe key). States: ok / needYou / alarm / cantCheck / empty(Set up).
- Each existing widget provider (`CarLiveSnapshot`/collection fetchers/etc.) writes a `GlanceFeed` for its kind on refresh (minimal hook — reuse the snapshot it already computes).
- [ ] A small tested helper if any logic (e.g. `glanceFeed(from: CarSnapshot)` mapping) → RED/GREEN; then the view+widget+registration; app+widget sim build SUCCEEDED; `#Preview` across states; suite + gate → commit `feat(ios): Glance widget`.

### Task 4: Add-a-widget gallery (re-skin)
**Files:** Create `Hearth/Widgets/AddWidgetGallery.swift`; the Preview tab + Settings link route to it (Task 8 finalises nav).
- Categorised sections **Control** (Alarm/Thermostat/Lights/Favourites/Quick), **Check** (Doors/Glance/Activity/Batteries), **Car & charging** (Car/ChargePoint). Each card = the existing `WidgetPreviewKind` specimen (reuse `widget(for:)`) + name + one-line desc; an **"Added"** green chip when `configuredWidgets(...)` includes it, a grey **"Needs Home Assistant"/"Needs ChargePoint"** chip when its connection isn't ready (04c), and a top "Connect" banner when HA not set up. Tapping a card → the per-widget page (Task 5). (The 04b "you already have one" sheet: optional; iOS is single-instance, so a tap can just open the page — implement the sheet only if cheap.)
- [ ] A tested helper `addWidgetChip(kind:config:cpSignedIn:) -> AddChip { .added, .needsHA, .needsCP, .ready }` in HearthKit → RED/GREEN; then the gallery view + previews; sim build; suite + gate → commit `feat(ios): Add-a-widget gallery`.

### Task 5: Per-widget page template
**Files:** Create `Hearth/Widgets/WidgetPage.swift` (+ Rename/Remove sheets); add a per-widget **display name** store (`Shared/WidgetNameStore.swift`, App-Group, keyed by kind) with a tested model.
- Template: pencil-editable title (display name, default = device/kind name) → salmon preview mat hosting the live specimen (reuse `widget(for:)`/the production Beacon view) + a Narrow/Standard/Wide segmented control + "Resize it on your home screen" caption → status line (`WidgetHealth` + `BeaconFreshness`: "On your home screen · updated 2 min ago" / "Example · yours appears after setup") → groups: **Uses** (the kind's `HaConfig` selection rows → existing pickers, amber "not found · Pick another" when a saved id is missing), **Safety** (Alarm only: "Hearth asks first" → `confirmWith`), **Shows** (Car only: capability chips + "Tap to open Tesla"), **Every day** (Alarm/Lights: Goodnight key row → `.settings` placeholder for Phase 5), **Look** ("Card style …" → Card-style page), **Remove from home screen** (→ instructional sheet 11d). Not-set-up (13): "Example" pill + a "Set up in N steps" card, no Remove.
- [ ] Failing test for `WidgetNameStore` (set/get/default) and a `widgetPageStatusLine(health:fresh:)` helper → RED/GREEN; then the page + sheets + previews (set-up / not-set-up / a couple kinds, light+dark); sim build; suite + gate → commit `feat(ios): per-widget settings page`.

### Task 6: CardStyle model + store (portable subset)
**Files:** Create `HearthKit/Sources/HearthKit/CardStyle/CardStyle.swift` + `Shared/CardStyleStore.swift`; Tests.
- `public struct CardStyle: Sendable, Codable, Equatable { background: CardBackground; textSize: CardTextSize; smallPrint: Bool }`, `public enum CardBackground { byState, colour(CardColour), black }`, `public enum CardTextSize { smaller, normal, larger }` with a scale factor. A global style + per-kind override: `CardStyleStore` (App Group) `style(for: HomeWidgetKind?) -> CardStyle` (override else global), `setGlobal`, `setOverride(kind:)`, `clearOverride(kind:)`. (NO corners/glass/wallpaper — per the ruling.)
- [ ] Failing tests (override beats global; textSize scale; round-trip Codable; default) → RED/GREEN → implement → PASS → suite + gate → commit `feat(ios): CardStyle model + store`.

### Task 7: CardStyle page + thread into widget content
**Files:** Create `Hearth/Widgets/CardStylePage.swift`; Modify the Beacon/Tile content to read `CardStyle` for text-size + small-print + background colour/Black (NOT the WidgetKit container shape).
- Page (17/18): a live preview card on the mat; Background segmented (By state / Colour / Black) + a colour picker when Colour; Text (Smaller/Normal/Larger); a "Show 'updated' time · Small print" `HearthSwitch`; and the per-widget "All widgets' style | Its own" segmented control (18) with an Undo affordance. A short caption explaining iOS shows the style on the card content (not the OS-drawn frame).
- Thread `CardStyle` into the shared Beacon content: text uses the size factor; the "Checked …" small-print shows/hides; the content background honours Colour/Black/By-state. Reads the kind's effective style from `CardStyleStore`.
- [ ] A tested helper `cardTextScale(_:) -> CGFloat` + the effective-style resolution already in Task 6; then the page + content threading + previews; app+widget sim build SUCCEEDED (confirm the widgets still render); suite + gate → commit `feat(ios): Card style page + content styling`.

### Task 8: Navigation wiring
**Files:** Modify `Hearth/HearthApp.swift` (`handleHomeRoute(.widget(kind))` → present `WidgetPage(kind)`; `.addWidget` → present `AddWidgetGallery`; the Preview tab → `AddWidgetGallery`), `Hearth/Home/LookSection.swift` (Card style row → `CardStylePage`), `Hearth/SettingsView.swift` (Widget-previews link → gallery). Keep TabView/gates/onOpenURL intact.
- [ ] Implement wiring; app sim build SUCCEEDED; deep-link funnel intact; suite + gate → commit `feat(ios): route to widget pages / gallery / card style`.

### Task 9: Verify + parity note
**Files:** none + `docs/PARITY-AUDIT.md`.
- [ ] DEBUG launch hooks (`-addGallery`/`-widgetPage`/`-cardStyle`/`-glancePreview`), screenshot vs mocks 04/11/16/17 + the Glance widget, shut sim, update PARITY-AUDIT ("## Widgets (Phase 4)" incl. the Card-style portable-subset divergence + that Glance is now the 11th widget). Commit `chore(ios): Phase 4 widgets parity note`.

## Notes
- Goodnight-key rows route to `.settings` until Phase 5.
- Per-widget display name is new App-Group state (not in HaConfig); keep it minimal, keyed by `HomeWidgetKind`.
- Card-style Corners/Glass/Wallpaper intentionally omitted (OS-controlled); the parity note records this platform divergence from mocks 17/18.
