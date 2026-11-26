# iOS Foundation & Design System Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Reconcile the feature-complete parity branch onto `main` (pipeline green), then build the shared iOS design system (tokens + components) that every later phase consumes.

**Architecture:** Design tokens and components live in a new `HearthKit/Sources/HearthKit/Design/` group so both the app target and the widget extension (both already depend on HearthKit) import one system. Tokens are plain Swift values (unit-testable); components are SwiftUI views with previews, their pure mapping logic unit-tested. Names mirror Android (`Theme.kt`, `SettingsKit.kt`).

**Tech Stack:** Swift 6, SwiftUI, iOS 17+, Swift Testing (`@Test`/`#expect`), XcodeGen, HearthKit SPM.

**Spec:** `docs/superpowers/specs/2026-11-26-ios-android-parity-port-design.md`

## Global Constraints

- iOS deployment target **17.0**; iPhone-only (`TARGETED_DEVICE_FAMILY = "1"` on app + widget targets — keep).
- Keep `main`'s pipeline settings in `project.yml`: generic `INFOPLIST_KEY_UISupportedInterfaceOrientations = UIInterfaceOrientationPortrait`, `INFOPLIST_KEY_ITSAppUsesNonExemptEncryption = NO`, widget version `$(MARKETING_VERSION)`/`$(CURRENT_PROJECT_VERSION)`.
- `xcodegen generate` output must stay in sync with tracked files — the CI test job runs `git diff --exit-code` after generating. Commit regenerated files (`project.yml`, any generated `Info.plist`) together.
- Swift Testing only (no XCTest). HearthKit tests run via `cd HearthKit && swift test`.
- Palette/type/metric values are copied **verbatim** from the spec's design-system section; no invented values.
- Tokens must resolve light **and** dark; nothing hard-codes a single scheme.

## Review Focus

- **Dark mode:** every token and component must render with the dark palette, not just light — pinned by Task 3 (color resolves per scheme) and each component preview carrying a `.preferredColorScheme(.dark)` variant.
- **Dynamic Type / large text:** the type ramp must scale and components must not clip at the largest accessibility size — pinned in Task 4 (font uses relative/scalable sizing) and Task 10 (row reflows, no fixed single-line truncation that drops content).
- **Missing Roboto Flex at runtime:** if the custom font fails to load, text must fall back to a system font, never render blank — pinned in Task 2.
- **Status tone correctness:** a "fixable problem" must map to amber and a healthy state to green (never swapped) — pinned in Task 6.
- **Pipeline stays green through the merge:** the 84-commit reconcile must not regress the TestFlight build — pinned in Task 1 (dispatch `ios-release.yml` and confirm success before the plan proceeds).

---

### Task 1: Reconcile the parity branch onto `main`

Integration task (not TDD): bring the feature-complete app onto `main` while keeping `main`'s pipeline settings, and prove the pipeline stays green.

**Files:**
- Modify: `project.yml` (conflict resolution only), whole tree merged from `codex/widget-platform-parity`.

**Interfaces:**
- Produces: a `main` that contains the full app (10 widgets, detail screens, ChargePoint engine, 14 AppIntents, ~60 HearthKit files) with the pipeline settings intact. All later tasks build on this `main`.

- [ ] **Step 1: Create a worktree on `origin/main`** and merge the branch:
  `git fetch origin`; `git worktree add -f /tmp/hearth-merge origin/main`; in it `git checkout -b reconcile-parity`; `git merge origin/codex/widget-platform-parity`.
- [ ] **Step 2: Resolve conflicts.** For `project.yml`, KEEP `main`'s version (device-family, orientation, compliance, widget version vars); additively re-add any *target/source/dependency* the branch introduced that main lacks (verify by diffing both `project.yml`s — expected: only the pipeline settings differ, so main's wins wholesale). Resolve any other conflicts in favor of the branch (it has the newer app code).
- [ ] **Step 3: Regenerate & verify in-sync:** `xcodegen generate` then `git diff --exit-code` → expect clean (no uncommitted generated drift).
- [ ] **Step 4: Run HearthKit tests:** `cd HearthKit && swift test` → Expected: PASS (the branch's suite).
- [ ] **Step 5: Build for simulator unsigned:** `xcodebuild -project Hearth.xcodeproj -scheme Hearth -sdk iphonesimulator -derivedDataPath /tmp/dd CODE_SIGNING_ALLOWED=NO build` → Expected: BUILD SUCCEEDED.
- [ ] **Step 6: Commit and push to main:** `git push origin HEAD:main`.
- [ ] **Step 7: Dispatch the release and confirm green:** `gh workflow run ios-release.yml --repo iRedlof/hearth-ios --ref main`; watch to completion → Expected: both jobs success, uploaded to TestFlight. If red, fix forward before any further task.

---

### Task 2: Bundle & register Roboto Flex

**Files:**
- Create: `Hearth/Resources/Fonts/RobotoFlex.ttf` (variable font, Apache-2.0).
- Modify: `project.yml` (app + widget targets: add the font to resources + `UIAppFonts`).
- Create: `HearthKit/Sources/HearthKit/Design/HearthFontRegistration.swift`.
- Test: `HearthKit/Tests/HearthKitTests/HearthFontTests.swift`.

**Interfaces:**
- Produces: `HearthFontRegistration.registerIfNeeded()` (idempotent, registers the bundled font with Core Text) and a guarantee the font family name string `"Roboto Flex"` is available; consumed by Task 4.

- [ ] **Step 1: Write the failing test** `test_robotoFlexFamilyIsRegistered()`: after `HearthFontRegistration.registerIfNeeded()`, assert `UIFont.familyNames.contains("Roboto Flex")`.
- [ ] **Step 2: Run** `cd HearthKit && swift test --filter HearthFontTests` → Expected: FAIL (symbol/font missing).
- [ ] **Step 3: Add the font file**, wire `UIAppFonts` in `project.yml` for both targets, and implement `registerIfNeeded()` using `CTFontManagerRegisterGraphicsFont` on the bundled font URL (guard: if the family already present, no-op). Fallback note: callers use `Font.custom("Roboto Flex", size:)` which Core Text resolves to system if absent — so absence degrades, never blanks.
- [ ] **Step 4: Run** the test → Expected: PASS.
- [ ] **Step 5: Regenerate & diff:** `xcodegen generate && git diff --exit-code` clean.
- [ ] **Step 6: Commit** `feat(ios): bundle and register Roboto Flex`.

---

### Task 3: Color tokens (`HearthColor`)

**Files:**
- Create: `HearthKit/Sources/HearthKit/Design/HearthColor.swift`.
- Test: `HearthKit/Tests/HearthKitTests/HearthColorTests.swift`.

**Interfaces:**
- Produces: `enum HearthColor` with static `Color` tokens resolving per scheme: `page, card, tint, line, ink, sub, mute, accent, onAccent, green, greenBg, amber, amberBg, red`. Backed by `func argb(light:UInt32, dark:UInt32) -> Color` (dynamic `UIColor`). Consumed by all component tasks.

- [ ] **Step 1: Write the failing test** `test_pageTokenResolvesLightAndDark()`: resolve `HearthColor.page` via a `UITraitCollection(userInterfaceStyle: .light)`/`.dark` and `#expect` the light hex `#F5F3EF` and dark hex `#111110` (compare resolved `UIColor` RGBA to the spec values within a small epsilon). Add a second assertion for `ink` (`#1C1B19` / `#F2EFEA`).
- [ ] **Step 2: Run** → FAIL.
- [ ] **Step 3: Implement** `argb(light:dark:)` via `UIColor { $0.userInterfaceStyle == .dark ? darkUIColor : lightUIColor }` wrapped in `Color`, and the token set with the spec's verbatim light/dark hex values.
- [ ] **Step 4: Run** → PASS.
- [ ] **Step 5: Commit** `feat(ios): warm palette color tokens`.

---

### Task 4: Type ramp (`HearthFont`)

**Files:**
- Create: `HearthKit/Sources/HearthKit/Design/HearthFont.swift`.
- Test: `HearthKit/Tests/HearthKitTests/HearthFontRampTests.swift`.

**Interfaces:**
- Consumes: Task 2's registered `"Roboto Flex"`.
- Produces: `enum HearthFont` → `Font` tokens: `largeTitle`(34, w450), `cardHeading`(19, w450), `pageTitle`(22, w450), `rowTitle`(15), `groupLabel`(13, w550), `subtitle`(12.5), `button`(14.5, w550), `pill`(12.5, w550). Each built on `Font.custom("Roboto Flex", size:, relativeTo:)` so it scales with Dynamic Type.

- [ ] **Step 1: Write the failing test** `test_rampSizesMatchSpec()`: a small table `[(token, expectedSize)]` for all 8 tokens; `#expect` each `HearthFont.spec(token).pointSize == expected` (expose a test-only descriptor `spec(_)` returning size+weight).
- [ ] **Step 2: Run** → FAIL.
- [ ] **Step 3: Implement** the tokens with the spec sizes/weights, each via `.custom(_,size:,relativeTo:)` mapped to the nearest text style so large text scales; expose `spec(_)` for the test.
- [ ] **Step 4: Run** → PASS.
- [ ] **Step 5: Commit** `feat(ios): Roboto Flex type ramp`.

---

### Task 5: Spacing & radius tokens (`HearthMetrics`)

**Files:**
- Create: `HearthKit/Sources/HearthKit/Design/HearthMetrics.swift`.
- Test: `HearthKit/Tests/HearthKitTests/HearthMetricsTests.swift`.

**Interfaces:**
- Produces: `enum HearthMetrics` CGFloat constants: `groupRadius=24, groupInset=16, rowMinHeight=62, rowSidePadding=16, iconTile=36, iconTileRadius=12, dividerInset=66, switchW=46, switchH=28, switchThumb=20, buttonH=40, buttonHSmall=32, chipH=30, miniCardW=174, miniCardRadius=22`.

- [ ] **Step 1: Write the failing test** `test_metricsMatchSpec()` asserting each constant equals the spec value.
- [ ] **Step 2: Run** → FAIL. **Step 3: Implement** the constants verbatim. **Step 4: Run** → PASS. **Step 5: Commit** `feat(ios): spacing & radius tokens`.

---

### Task 6: `StatusTone` + `StatusPill`

**Files:**
- Create: `HearthKit/Sources/HearthKit/Design/StatusPill.swift`.
- Test: `HearthKit/Tests/HearthKitTests/StatusToneTests.swift`.

**Interfaces:**
- Consumes: Task 3 colors, Task 4/5 tokens.
- Produces: `enum StatusTone { case ok, warn, neutral }` with `var colors: (bg: Color, ink: Color)` (ok→green/greenBg, warn→amber/amberBg, neutral→mute/tint); `struct StatusPill: View` (dot + word, `init(_ text:String, tone:StatusTone)`).

- [ ] **Step 1: Write the failing test** `test_toneMapsToCorrectColors()`: `#expect` `.ok.colors.bg` resolves to greenBg and `.warn.colors.bg` to amberBg (resolve via light trait, compare to spec hex). This pins "fixable problem = amber, healthy = green, never swapped."
- [ ] **Step 2: Run** → FAIL. **Step 3: Implement** the mapping + the `StatusPill` view; add a `#Preview` with ok/warn/neutral in light and dark. **Step 4: Run** → PASS. **Step 5: Commit** `feat(ios): StatusTone + StatusPill`.

---

### Task 7: `TileHue` + `IconTile`

**Files:**
- Create: `HearthKit/Sources/HearthKit/Design/IconTile.swift`.
- Test: `HearthKit/Tests/HearthKitTests/TileHueTests.swift`.

**Interfaces:**
- Produces: `enum TileHue { case blue, orange, purple, green, red, amber, neutral }` with `var colors:(fill:Color, ink:Color)` (light+dark per spec `TileHue`); `struct IconTile: View` (`init(systemName:String, hue:TileHue)`, 36pt, 12pt radius, 20pt glyph).

- [ ] **Step 1: Write the failing test** `test_hueColorsResolve()` for 2 hues (blue, green) in light+dark vs spec values.
- [ ] **Step 2–4:** FAIL → implement mapping + view + light/dark `#Preview` → PASS. **Step 5: Commit** `feat(ios): TileHue + IconTile`.

---

### Task 8: `HearthSwitch`

**Files:**
- Create: `HearthKit/Sources/HearthKit/Design/HearthSwitch.swift`.
- Test: `HearthKit/Tests/HearthKitTests/HearthSwitchTests.swift`.

**Interfaces:**
- Produces: `struct HearthSwitch: View` (`init(isOn: Binding<Bool>)`): 46×28 track, 20 thumb, ink track when on, tint when off; tap toggles the binding.

- [ ] **Step 1: Write the failing test** `test_switchGeometryFromMetrics()`: expose a test-only `HearthSwitch.Geometry` struct derived from `HearthMetrics` and `#expect` trackWidth==46, thumb==20 (pins geometry without snapshotting the view).
- [ ] **Step 2–4:** FAIL → implement the view + geometry + an interactive `#Preview` (on/off, light/dark) → PASS. **Step 5: Commit** `feat(ios): HearthSwitch`.

---

### Task 9: `InkButton` + `InlineRowButton`

**Files:**
- Create: `HearthKit/Sources/HearthKit/Design/HearthButtons.swift`.
- Test: `HearthKit/Tests/HearthKitTests/HearthButtonsTests.swift`.

**Interfaces:**
- Produces: `struct InkButtonStyle: ButtonStyle` (solid ink pill, `onAccent` label, height 40, radius ~20) and `struct InlineRowButtonStyle: ButtonStyle` (tonal, height 32); convenience `Button.hearthInk()` / `.hearthInline()` modifiers.

- [ ] **Step 1: Write the failing test** `test_buttonHeightsFromMetrics()` asserting the styles' configured heights equal `HearthMetrics.buttonH` / `buttonHSmall` (expose the heights as static constants on the styles).
- [ ] **Step 2–4:** FAIL → implement the two `ButtonStyle`s + `#Preview` → PASS. **Step 5: Commit** `feat(ios): ink & inline button styles`.

---

### Task 10: `HearthGroup` + `HearthRow` primitives

**Files:**
- Create: `HearthKit/Sources/HearthKit/Design/HearthGroup.swift`, `HearthKit/Sources/HearthKit/Design/HearthRow.swift`.
- Test: `HearthKit/Tests/HearthKitTests/HearthRowTests.swift`.

**Interfaces:**
- Consumes: Tasks 3–9.
- Produces:
  - `struct HearthGroup<Content: View>: View` (`init(_ label: String? = nil, @ViewBuilder content:)`) — optional `groupLabel`, inset card (`groupRadius`, `groupInset`), auto divider inset `dividerInset` between rows.
  - `struct HearthRow<Trailing: View>: View` (`init(icon: String, hue: TileHue, title: String, subtitle: String? = nil, subtitleWarn: Bool = false, @ViewBuilder trailing:)`) — `IconTile` + title(`rowTitle`) + subtitle(`subtitle`, amber when `subtitleWarn`) + trailing control, `rowMinHeight`, side padding.

- [ ] **Step 1: Write the failing test** `test_rowSubtitleWarnUsesAmber()`: expose a test-only `HearthRow.resolvedSubtitleColor(warn:)` and `#expect` `warn==true` → `HearthColor.amber`, `false` → `HearthColor.sub`. (Pins "amber only when there's a problem" and keeps the view testable without snapshots.)
- [ ] **Step 2: Run** → FAIL.
- [ ] **Step 3: Implement** both views; the row must let its title/subtitle wrap (no fixed 1-line truncation that drops content) so large text reflows. Add a `#Preview` assembling a sample **Connections** group (Home Assistant row with green pill, ChargePoint row with amber "Needs sign-in") in light and dark and at `.environment(\.sizeCategory, .accessibilityExtraLarge)`.
- [ ] **Step 4: Run** → PASS.
- [ ] **Step 5: Commit** `feat(ios): HearthGroup + HearthRow primitives`.

---

### Task 11: Phase-1 parity snapshot (verification deliverable)

**Files:** none (verification + doc).

- [ ] **Step 1:** Build a tiny SwiftUI preview screen (`DesignSystemGallery`, under `#if DEBUG`) composing every component (pills, tiles, switch, buttons, a sample group) light + dark.
- [ ] **Step 2:** Run it in the simulator, screenshot light + dark, and place side-by-side with `final-v2/01-home.png`'s component details to confirm palette/type/radius read the same.
- [ ] **Step 3: Commit** `chore(ios): design-system gallery preview` and note in `docs/PARITY-AUDIT.md` that Phase 1 (design system) is complete.

---

## Notes for the next plan (Phase 2 — Home dashboard)

Phase 2 consumes everything above. It adds the cross-widget **status model** (`WidgetHealth` signal + problem-first sort) in HearthKit, then the `HomeView` dashboard (large title, Your-widgets strip, Connections/Every-day/Look groups, version footer) and its states. It also performs the AppIntent/`widgetURL` deep-link audit so collapsing the 3-tab shell to NavigationStack breaks nothing. Written as its own plan once Phase 1 lands.
