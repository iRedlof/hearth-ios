# Hearth iOS — Android look & UX parity port (design)

Date: 2026-11-26
Status: proposed (awaiting owner approval)
Owner: Rohit Chandani

> **Scope decision (owner, 2026-11-26):** full parity in ONE wave — port both the
> look AND the Android features that iOS lacks today (Morning commute, Routines,
> Leave-by, Travel days, Safety alerts, Goodnight, onboarding/alarm-setup
> stepper), plus the **Glance** widget for 11-tile gallery parity. These are real
> feature builds (permissions, scheduling, notifications, tests), not re-skins.
> This is a multi-week project; each phase still ships green through the pipeline.

## Intent & why

Hearth ships on Android (mature, feature-rich, recently redesigned "v2") and iOS
(now installable via TestFlight, but visually and structurally outdated). The
iOS app is essentially WidgetKit "Beacon" cards stacked in a scroll view, with
stock `Form` settings and no design system. The owner wants iOS brought up to
the Android v2 look and UX so the two platforms feel like one product —
"homogeneous cross-platform." The widgets themselves are already strong on iOS;
the gap is the **app chrome** (home dashboard, settings, onboarding, flows) and
the **absence of a shared design language**.

The Android v2 design already exists as 60 finished, approved mockups (PNG +
HTML, light/dark, every state) in
`hearth-task-artifacts/hearth-settings/final-v2/`. That is the authoritative
"after" target for this port — we translate it to SwiftUI rather than invent it.

## Goals

- A real iOS **design system** (tokens + components) ported from Android's
  `Theme.kt` / `SettingsKit.kt` / `CardStyle.kt`: warm palette (light+dark),
  Roboto Flex type ramp (Book 450 / Semi 550, 34pt large title), spacing/24pt
  card radius, and components `HearthSwitch`, `StatusPill`, `IconTile`,
  `InkButton`, group card, row.
- The Android v2 **Home dashboard**: large "Hearth" title, "Your widgets" strip
  (problems first, live state lines), **Connections** and **Every day** groups,
  **Look** row, version footer — status-first, problems bubble to the top.
- **Settings v2** as per-thing pages (Home Assistant, ChargePoint + Alerts +
  Morning commute) each led by an honest status hero, not a flat toggle list.
- **Widget flow**: Add-a-widget gallery → per-widget page template (live hero on
  peach stage, "Preview at" sizes, fixed groups Uses/Safety/Shows/Every day/
  Look/Remove) → Card style (all or per-widget).
- **Flows & features** (NEW on iOS — real builds matching Android behaviour):
  numbered onboarding/alarm-setup stepper; Routines (learning + cards);
  Leave-by / Travel days (calendar access); Safety alerts (local notifications);
  Goodnight key; Morning commute (geofence + drive-time join); entity pickers
  (limit ring, search, discard guard).
- The **Glance** small summary widget (new WidgetKit widget) so the Add-a-widget
  gallery matches the 11-tile mock.
- A **cross-widget status model** in HearthKit: a uniform, sortable health
  signal per widget so the Home "Your widgets" strip can surface problems first.
- Light + dark + large-text parity; eased, 60fps motion; a literal side-by-side
  check of built screens against the mocks.

## Non-goals

- Re-implementing widget rendering logic or the ChargePoint account/auto engine
  — those exist and work on the parity branch; this port re-skins their existing
  surfaces onto the new design system (distinct from the NEW feature ports above).
- Pixel-identical cloning of Android. We match the visual *language* (palette,
  type, components, IA, states) implemented idiomatically in SwiftUI.
- Any feature that does not already exist on Android. We port to Android parity,
  no further. (The iOS-absent features listed in Goals ARE in scope — they exist
  on Android.)
- iPad/universal layout. iOS stays iPhone-only (TARGETED_DEVICE_FAMILY=1).
- App Store (public) submission. TestFlight internal/external only, as today.

## Anti-goals (what would make this a failure even if it "works")

- Re-introducing ad-hoc styling (inline magic numbers) instead of shared tokens —
  that is exactly what makes today's app feel basic.
- A dashboard that looks like Android but loses the "status is always honest"
  behaviour (stale/offline/paused shown truthfully).
- Breaking the now-green TestFlight CI/CD pipeline or the working widgets /
  AppIntents during the re-skin.

## Constraints

- **Stack:** SwiftUI, Swift 6, iOS 17+, XcodeGen (`project.yml` → gitignored
  `Hearth.xcodeproj`), HearthKit SPM package. iPhone-only.
- **Pipeline:** releases go through `.github/workflows/ios-release.yml` on
  `main` (self-hosted `xcode-27`); the test job runs `xcodegen generate` + `git
  diff --exit-code` + `swift test`, so any `project.yml` / generated-plist change
  must be committed in sync. Keep the device-family=1, generic-orientation, and
  export-compliance settings already on main.
- **Source of truth for the look:** `hearth-task-artifacts/hearth-settings/
  final-v2/` (mocks) + Android `Theme.kt`, `SettingsKit.kt`, `CardStyle.kt`,
  `BeaconMetrics.kt`.
- **Reuse:** the `codex/widget-platform-parity` branch (84 commits ahead of
  main) holds the feature-complete iOS app — 10 widgets, detail screens, CP
  sign-in/ownership/auto engine, 14 interactive AppIntents, ~60 HearthKit files,
  large test suite. We build on it, not from scratch.

## Approaches considered

**A. Rebuild the iOS UI from scratch on main, matching the mocks.**
Clean slate, but throws away 84 commits of working widgets, detail screens, the
ChargePoint engine, and the test suite — months of logic we'd have to re-derive.
Rejected: enormous waste and regression risk against functionality that already
passes tests.

**B. Re-skin in place on the parity branch, keep developing there.**
Fast to start, but leaves main and the branch diverging further, fights the
owner's "single main branch" goal, and the branch predates the pipeline fixes
now on main (project.yml device-family/orientation/compliance). Rejected: the
divergence and pipeline-regression risk compound.

**C (chosen). Reconcile the parity branch onto main first, then port the chrome
on a new design system.**
Step 0 merges the parity branch's functionality into `main`, resolving
`project.yml` to KEEP main's pipeline settings, and verifies tests + a TestFlight
dispatch still pass. Then phases 1–6 build the design system and re-skin the
chrome screen by screen on top of that reconciled main. This preserves all
working logic, collapses toward one `main` branch (an explicit owner goal), and
keeps every change flowing through the green pipeline.

Chosen: **C.** It keeps the working functionality, honours the single-branch
goal, and never takes the pipeline out of the green.

## The how (decided)

- **Build on the reconciled parity code** (Approach C). Step 0 is a careful merge
  of `codex/widget-platform-parity` → **`origin/main`** (not the stale local
  `main`, which sits at the merge-base), keeping main's `project.yml` pipeline
  settings; the 11 commits main is "ahead" are purely CI + project.yml, so the
  conflict is narrow. Then `swift test` + a dispatch build to confirm green.
- **Design-system-first.** Phase 1 creates `HearthKit` (or app-level) design
  tokens + components before any screen is re-skinned, so every subsequent screen
  consumes the system (no ad-hoc styling).
- **Native SwiftUI matching the Android visual language**, not a literal clone.
- **Ship Roboto Flex** (the custom 450/550 weights + 34pt optical-size title) as
  a bundled font so type matches Android exactly; Material Symbols Rounded →
  mapped to SF Symbols or a bundled symbol set where an exact glyph matters.
- **Phased, each verified before the next**, in this order:
  1. **Design system** (tokens + components, with SwiftUI previews).
  2. **Home dashboard** (+ states: first-run, needs-sign-in, offline, toast,
     dark, large-text) + the cross-widget **status model** that orders problems
     first.
  3. **Settings v2 re-skin** — Home Assistant page, ChargePoint page + Alerts
     (re-skin existing logic onto the new system).
  4. **Widgets** — Add-a-widget gallery, widget-page template, Card style (keep
     the existing Beacon renders; wrap them in the flow + peach-stage previews).
     **Build the Glance widget** (new WidgetKit widget) for 11-tile parity.
  5. **New feature ports** (each = logic + permissions + tests, matching
     Android), skinned on the design system:
     - Onboarding / **alarm-setup stepper** (computed steps, empty states).
     - **Routines** (learning + cards) — background observation + suggestions.
     - **Leave-by** and **Travel days** — EventKit calendar access.
     - **Safety alerts** — local notifications + permission prompt.
     - **Goodnight** key.
     - **Morning commute** — on-device geofence (Core Location, always auth) +
       Google Routes drive-time join, mirroring Android's on-phone commute
       (ChargePoint "Morning commute" sub-page). Off by default.
     - Entity **pickers** (limit ring, search, discard guard).
  6. **Polish & parity pass** — light/dark, large-text, eased motion,
     side-by-side mock check across all screens.
- **Each phase**: TDD where logic is involved (HearthKit view models / state),
  SwiftUI previews for every new component/screen, and a simulator screenshot
  diffed against the corresponding `final-v2` mock before moving on.

## iOS-reality notes (baked into the plan)

1. **"Add to Home Screen."** iOS cannot programmatically place a widget on the
   Home Screen (unlike Android). The Add-a-widget flow will present the widget,
   confirm it's configured/ready, and instruct the user to add it via the iOS
   widget gallery (with a short "how" affordance) — wording matched to what iOS
   allows, not Android's auto-place.
2. **Fonts.** Roboto Flex + the needed symbol glyphs are bundled so type and
   iconography match Android; we don't rely on system SF for the editorial title.
3. **Settings "tab" vs pages, and the Preview tab.** Android folds settings into
   the home groups rather than a separate Settings tab, and reaches the widget
   gallery via a "Look → Widget previews" row. The current iOS 3-tab shell (Live/
   Settings/Preview) collapses toward that IA: Home is the dashboard; settings
   and the gallery are pages reached from its groups (Preview tab → an
   "Add a widget / previews" entry under Look). Default to push-navigation-from-
   Home (NavigationStack); exact nav style is a Phase-2 detail.
4. **AppIntent / widgetURL deep-links must survive the nav change.** The app has
   14 interactive AppIntents and small-widget deep links that today target tabs.
   Step 0 / Phase 2 audits every `widgetURL` and intent target and re-points them
   to the new NavigationStack routes so nothing breaks when the tab shell goes.

## Capabilities, permissions & platform mechanics (for the feature ports)

Each new feature needs an iOS capability the app doesn't request today; all are
added to `project.yml` entitlements / Info.plist usage strings as its phase lands:

- **Morning commute:** Core Location "Always" authorization + a geofence region
  around the charger; background location; a Google Routes API key (as on
  Android). Off by default; opt-in in ChargePoint settings.
- **Leave-by / Travel days:** EventKit (calendar) read access + usage string.
- **Safety alerts / commute nudges / Routines:** `UNUserNotificationCenter`
  local notifications + permission prompt; background refresh
  (`BGTaskScheduler`) for scheduled checks.
- **Routines learning:** local, on-device observation store (no server); mirrors
  Android's learned-cards model.
All permission prompts are triggered by explicit user action (enabling the
feature), never at launch, with graceful "permission denied" states (the mocks
include e.g. "calendar denied", "notifications off").

## What's left to the builder

- Exact SwiftUI token/component API shape (naming, where tokens live:
  HearthKit vs app target) — builder's call, following the Android names.
- Navigation implementation (NavigationStack routing, sheet presentations).
- How peach-stage/`WallpaperBackdrop` is rendered in SwiftUI (gradient + blur).
- Mapping Material Symbols → SF Symbols vs bundled glyphs, per-icon.
- Test strategy specifics per phase (which view models get unit tests).
- The parity-branch → main merge conflict resolution details (Step 0).

## Reference

- Mocks: `hearth-task-artifacts/hearth-settings/final-v2/` (+ `html/`, `src/`),
  `ONE-BOARD.png`, `PLAN.md`, `SIMPLICITY.md`, `01-settings-map.md`.
- Android design source: `app/src/main/java/com/rohit/hearth/` — `Theme.kt`,
  `SettingsKit.kt`, `CardStyle.kt`, `CardLook.kt`, `WallpaperBackdrop.kt`,
  `HomeScreen.kt`, `SettingsList.kt`, `BeaconChrome.kt`, `BeaconScale.kt`.
- iOS current: `Hearth/HearthApp.swift`, `LiveDashboardView.swift`,
  `SettingsView.swift`, `Shared/*BeaconView.swift`,
  `HearthKit/.../BeaconTone.swift`, `docs/PARITY-AUDIT.md`.
- Review boards (this session): `.superpowers/brainstorm/.../content/*.html`.
