# iOS Phase 5a — Morning Commute (ChargePoint auto-join) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development. Steps use checkbox (`- [ ]`).

**Goal:** Port Android's fully-built Morning-commute feature to iOS: auto-join the ChargePoint waitlist on weekday-morning departures, driven by two Home-Assistant boolean sensors (HA does the geofence/ETA via Google Routes), with an in-app settings page (toggles + copy-paste HA YAML + detection status) and integration into the existing ChargePoint widget refresh.

**Architecture:** Port the pure decision function `commuteDecide` 1:1 into HearthKit as `ChargePointCommute.swift`, mirroring the existing `ChargePointAuto.swift` (pure `Sendable`/`Equatable` types, verbatim-port provenance comment, UserDefaults day-stamp persistence). The iOS runtime already has the pieces: `cpAutoDecide` engine, BGTaskScheduler 15-min refresh, HA template fetch, and the ChargePoint widget timeline. Morning-commute reads two HA sensors in the same refresh and feeds `commuteDecide`, which emits `.armAuto` / `.notifySignIn` / `.none`. New SwiftUI page in the app target; reuse existing pickers/design system/notification helper (`CpNotify`).

**Tech Stack:** SwiftUI, WidgetKit, Swift 6 strict concurrency, iOS 17+, Swift Testing + XCTest, XcodeGen, HearthKit.

**Spec:** design doc Phase 5 (`docs/superpowers/specs/2026-11-26-ios-android-parity-port-design.md`); mocks `final-v2/10-morning-commute.png`, `10b`. Android source (authoritative, port verbatim): `/Volumes/xHome/Github/hearth/app/src/main/java/com/rohit/hearth/ChargePointCommute.kt`; Android tests to port: `/Volumes/xHome/Github/hearth/app/src/test/java/com/rohit/hearth/ChargePointCommuteTest.kt`. iOS pattern to mirror: `HearthKit/Sources/HearthKit/ChargePointAuto.swift`.

## Global Constraints
- iOS 17; iPhone-only. Swift 6 `SWIFT_STRICT_CONCURRENCY = complete`. HearthKit code is PURE/`Sendable`/UIKit-free and macOS-`swift test`-runnable — the engine + all logic live there; WidgetKit/UNUserNotifications usage stays in the app/widget/Shared targets.
- `@Dependency`/no-`Date()`-in-logic discipline: the engine takes `today`/`now` as parameters (like `cpAutoDecide` takes `now`), never reads the clock itself — keeps it deterministic and testable.
- `xcodegen generate` + `git diff --exit-code` must stay clean (generated project committed in sync). App + widget sim build must pass: `xcodebuild -project Hearth.xcodeproj -scheme Hearth -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build` → BUILD SUCCEEDED. **The controller verifies the APP-TARGET build itself — the HearthKit `swift test` count passes even when the app/widget targets fail to compile.**
- Design tokens (HearthColor/HearthFont/HearthMetrics) for all colours/fonts; no hardcoded style values. Match the existing Settings-page/`HearthGroup`/`HearthRow` patterns.
- No new app API keys. Google Routes lives in the owner's HA config (not the app); the app only reads HA sensor values. The two sensors ship as copy-paste YAML with Copy buttons showing exact text.
- Notifications are explicit opt-in with denied-state handling, reusing the `CpNotify` authorization pattern.

## Review Focus
- **Never arms twice in a day:** `commuteDecide` must not emit `.armAuto`/`.notifySignIn` more than once per calendar day (guarded by `lastArmDay`/`lastNotifyDay` vs `today`). Task 1 tests.
- **Honest detection status:** the page's "Found / Last heard HH:MM / Waiting" state reflects real last-sensor-read time, never a hardcoded "Found". Task 4 tests the mapper.
- **Signed-out/charging/already-armed short-circuits:** decision returns `.none` when charging, already armed today, or disabled — verify each branch (Task 1, ported tests).
- **Corrupt/missing day-stamps:** unreadable persisted day-stamp → treated as "no prior action today" (safe: allows today's action), never a crash. Task 2 tests.
- **Permission denied:** toggling commute ON when notifications are denied shows the amber Settings-deep-link banner, doesn't silently no-op. Task 4.

---

### Task 1: Port the `commuteDecide` engine + types (pure, tested)
**Files:** Create `HearthKit/Sources/HearthKit/ChargePointCommute.swift`; Test `HearthKit/Tests/HearthKitTests/ChargePointCommuteTests.swift`.
Port 1:1 from Android `ChargePointCommute.kt`, mirroring `ChargePointAuto.swift`'s structure and provenance-comment style. Produce:
- `public enum CommuteAction: Sendable, Equatable { case armAuto, notifySignIn, none }`
- `public func commuteDecide(enabled: Bool, chargeNow: Bool, signinNeeded: Bool, alreadyArmed: Bool, charging: Bool, signedOutOrExpired: Bool, lastArmDay: <DayStamp>?, lastNotifyDay: <DayStamp>?, today: <DayStamp>) -> CommuteAction` — exact branch logic from the Kotlin (read it; do not guess). Represent the Android `LocalDate` as a simple `Sendable`/`Equatable` day value (e.g. `public struct CommuteDay: Sendable, Equatable { let year, month, day: Int }` or an `Int` yyyymmdd) — choose whichever makes the day-equality checks trivial and matches how `today` will be computed in the app from `@Dependency(\.date)` in `TimeZone.current`.
- [ ] Port all scenarios from Android `ChargePointCommuteTest.kt` (expect ~12) as Swift Testing `@Test`s covering: enabled/disabled, chargeNow→armAuto, signinNeeded→notifySignIn, already-armed-today→none, charging→none, signed-out→(per Kotlin), same-day re-entry→none, next-day→acts again. Write failing → implement port → pass → full suite + gate clean → commit `feat(ios): port Morning-commute decision engine`.

### Task 2: Day-stamp persistence (pure + store)
**Files:** Modify `ChargePointCommute.swift` (add `commuteDayToWire`/`fromWire` or an `Int` yyyymmdd mapping, pure) ; Create `Shared/CommuteStore.swift` (App-Group UserDefaults: `lastArmDay`/`lastNotifyDay` get/set, `enabled` flag); Tests for the pure mapping.
- [ ] Failing tests: day round-trips wire form; corrupt/empty → nil (→ engine treats as "no action today"); set/get. Implement → pass → suite + gate → commit `feat(ios): Morning-commute day-stamp persistence`.

### Task 3: HA sensor fetch for the two commute booleans
**Files:** Modify the existing HA template-fetch path used by ChargePoint (find it — the research notes a template pattern already exists for CP). Add a fetch for `binary_sensor.commute_charge_now` and `binary_sensor.commute_signin_needed` returning `(chargeNow: Bool, signinNeeded: Bool, lastHeard: Date)`.
- Reuse the existing HA template request builder; do NOT add a new auth/transport path. Template body: `{{ is_state('binary_sensor.commute_charge_now','on') }}|{{ is_state('binary_sensor.commute_signin_needed','on') }}`.
- [ ] A tested pure parser `parseCommuteSensors(_ body: String) -> (chargeNow: Bool, signinNeeded: Bool)?` in HearthKit (corrupt/short → nil) → RED/GREEN; then the fetch wiring; suite + gate → commit `feat(ios): read HA commute sensors`.

### Task 4: MorningCommutePage (UI)
**Files:** Create `Hearth/Settings/MorningCommutePage.swift`; a tested status mapper in HearthKit.
- Page (mocks 10/10b): an Enable toggle; a "Detection" status row — **Found** (green) when last sensor read is fresh, **Last heard HH:MM** when stale, **Waiting** (amber) when never heard — from a pure `commuteStatus(lastHeard:now:) -> CommuteStatus` helper (tested, honest, never hardcoded "Found"); two "Copy HA config" buttons that copy the exact sensor YAML to the clipboard (show the YAML in a monospaced block); a notifications amber banner with a Settings deep-link when `UNUserNotificationCenter` authorization is denied (reuse `CpNotify`'s pattern). Design tokens throughout; match existing Settings page structure.
- [ ] Failing tests for `commuteStatus(lastHeard:now:)` (fresh→found; stale→lastHeard; nil→waiting) → RED/GREEN; then the page + previews (enabled/denied/waiting, light+dark); app sim build SUCCEEDED (controller-verified); suite + gate → commit `feat(ios): Morning-commute settings page`.

### Task 5: Integrate commute into the ChargePoint widget refresh
**Files:** Modify the ChargePoint provider/timeline refresh (where `cpAutoDecide` / the 15-min BGTask refresh runs) to also: read the two sensors (Task 3), build `today` from `@Dependency(\.date)` in `TimeZone.current`, call `commuteDecide`, and act — `.armAuto` → the existing CP auto-join/arm path + stamp `lastArmDay`; `.notifySignIn` → a `CpNotify` "sign in to ChargePoint" notification + stamp `lastNotifyDay`; `.none` → nothing. Respect the enabled flag.
- Capture specific values before any `.run`/async closure (never capture whole state) per the TCA/gotchas rules.
- [ ] A tested helper if any mapping logic (e.g. action→sideeffect selection) → RED/GREEN; then the integration; app+widget sim build SUCCEEDED; suite + gate → commit `feat(ios): run Morning-commute in ChargePoint refresh`.

### Task 6: Nav wiring + verify + parity note
**Files:** Modify the Settings/ChargePoint page to route to `MorningCommutePage` (match the existing Settings routing — likely a `HearthSheet`/`HomeRoute` addition or a row in the ChargePoint settings page); add a DEBUG launch hook `-morningCommute`; update `docs/PARITY-AUDIT.md` with a "## Morning commute (Phase 5a)" section (feature at parity; note Google-Routes-is-HA-side; note the two sensors ship as copy YAML; record the never-twice-a-day guarantee).
- [ ] Implement routing; DEBUG hook; app sim build SUCCEEDED; deep-link funnel intact; PARITY-AUDIT updated; suite + gate → commit `chore(ios): wire Morning-commute nav + parity note`.

## Notes
- The engine is the only hard part and it is a verbatim port with existing tests — keep it exact; the UI/integration reuse established iOS patterns.
- `today`/`now` always come from `@Dependency(\.date)` in `TimeZone.current` (ISO/UTC off-by-one risk — see gotchas); the engine never reads the clock.
- This plan ships Morning-commute independently; Alarm-setup v2 and the net-new features (Routines, Leave-by, Travel, Safety, Goodnight) are separate Phase-5 plans (5b/5c).
