# iOS Phase 5c (part 1) — Goodnight Key Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development. Steps use checkbox (`- [ ]`).

**Goal:** Build the net-new **Goodnight Key** — a one-tap bedtime automation (Close garage → Lights off except keep-on → Lock door → Arm Night), runnable from the lock screen via an App Intent, active only within a configurable night window (default 9 PM–5 AM), with a settings page and a "no alarm set up" state.

**Architecture:** Net-new (Android planned-only). All DECISION logic pure + macOS-tested in HearthKit (time-window with overnight wrap; arm-mode fallback). HA actions reuse the existing runtimes (`AlarmActionRuntime` for arm + lock) plus two new thin HA-service helpers (cover close; batch lights-off). A lock-screen `RunGoodnightIntent` (AppIntent, `openAppWhenRun=false`) runs the sequence, gated on the window. Settings page + Every-day nav. App-Group config store.

**Tech Stack:** SwiftUI, AppIntents, Swift 6 strict concurrency, iOS 17+, Swift Testing + XCTest, XcodeGen, HearthKit.

**Spec:** design doc Phase 5; mocks `final-v2/23-goodnight-key.png` (on), `23b-goodnight-key-no-alarm.png` (no-alarm). No Android source.

## Global Constraints
- iOS 17; iPhone-only; Swift 6 `complete`. HearthKit logic pure/`Sendable`/UIKit-free/macOS-testable; HA/AppIntent/UI code in app targets. **Controller verifies the APP-TARGET build itself.**
- `xcodegen generate` + `git diff --exit-code` clean. App sim build passes.
- Design tokens (HearthColor/HearthFont/HearthMetrics; HearthGroup/HearthRow/HearthSwitch); `Date.FormatStyle`; times computed in `TimeZone.current`. No bare magic style numbers (icon sizes via HearthMetrics constants).
- HA actions reuse existing service-call infra (`HaClient.callService`); do NOT add a new transport/auth path.

## Rulings baked in (see ledger)
- **G1** Garage = the cover entities already configured in the Doors widget (filter `cover.`); no new picker.
- **G2** Lights-off = all `light.*` from `/api/states` EXCEPT the keep-on list.
- **G3** Arm fallback: panel without Night → silently use Home; settings shows "Night (Home if unavailable)".
- App Intents + lock screen (`openAppWhenRun=false`), NOT CoreNFC.

## Review Focus
- **Overnight window wrap:** 9 PM–5 AM crosses midnight — `goodnightActive` must be true at 11 PM AND 2 AM, false at noon. Off-by-wrap is the most likely bug (Task 2 tests).
- **No step aborts the rest:** if lights-off fails, the door must still lock and the alarm still arm — the sequence collects failures but doesn't short-circuit the safety-critical lock/arm (Task 4 tests/review).
- **Lock-screen gating:** `RunGoodnightIntent` outside the window does nothing (or a clear message), never silently arms at the wrong time (Task 5).
- **No-alarm state honest:** when no alarm widget/entity is configured, the page shows the 23b "Uses the Home key on an Alarm widget · Add Alarm" state, not a broken config (Task 6).
- **Keep-on respected:** a light in the keep-on list is never turned off (Task 3 tests).

---

### Task 1: GoodnightConfig model + store
**Files:** Create `HearthKit/Sources/HearthKit/Goodnight/GoodnightConfig.swift`; `Shared/GoodnightStore.swift`; Tests.
- `public struct GoodnightConfig: Sendable, Codable, Equatable { public var enabled: Bool; public var startHour: Int; public var endHour: Int; public var armMode: GoodnightArmMode; public var keepOnLights: [String]; public init(...) }` with `.default` (enabled false, startHour 21, endHour 5, armMode .night, keepOnLights []). `public enum GoodnightArmMode: String, Sendable, Codable { case night, home }`.
- `GoodnightStore` (App-Group `group.com.rohit.hearth`, mirror `CommuteStore`/`CardStyleStore`): load/save the config; absent → `.default`; corrupt → `.default` (never crash).
- [ ] Failing tests (round-trip Codable; absent→default; corrupt→default; arm-mode raw values) → RED/GREEN → suite+gate → commit `feat(ios): Goodnight config model + store`.

### Task 2: Pure window + arm-fallback logic
**Files:** Create `HearthKit/Sources/HearthKit/Goodnight/GoodnightLogic.swift`; Tests.
- `public func goodnightActive(now: Date, startHour: Int, endHour: Int, calendar: Calendar) -> Bool` — true when the local hour is within [startHour, endHour) treating a start>end as an OVERNIGHT wrap (e.g. 21..5 means 21:00–23:59 and 00:00–04:59). Use the passed calendar's timezone.
- `public func resolveArmMode(preferred: GoodnightArmMode, panelSupportsNight: Bool) -> GoodnightArmMode` — `.night` preferred but `!panelSupportsNight` → `.home`; else preferred.
- [ ] Failing tests: active at 23:00 and 02:00 for 21..5; inactive at 12:00; boundary at exactly startHour (active) and endHour (inactive); a non-wrap window (e.g. 1..5); arm fallback night→home when unsupported, stays night when supported, home stays home. Timezone honored. RED/GREEN → suite+gate → commit `feat(ios): Goodnight window + arm-mode logic`.

### Task 3: HA action helpers (cover close + batch lights-off)
**Files:** Add helpers near the existing HA action code (find `GarageGate`/`HaClient.callService` and `LightToggleIntent`); a tested pure `lightsToTurnOff(all: [String], keepOn: [String]) -> [String]` in HearthKit.
- `lightsToTurnOff(all:keepOn:)` — all `light.*` ids minus the keep-on set (order-stable, deduped). PURE + tested.
- A `closeCover(id:)` helper (`cover.close_cover`) and a `turnOffLights(ids:)` batch (loop or HA array form) in the app/HA layer, reusing `HaClient.callService`.
- [ ] Failing tests for `lightsToTurnOff` (excludes keep-on; empty keep-on → all; keep-on not in all → no-op; dedupe) → RED/GREEN; then the two HA helpers; suite+gate → commit `feat(ios): cover-close + batch lights-off helpers`.

### Task 4: GoodnightRuntime (sequential executor)
**Files:** Create `Shared/GoodnightRuntime.swift`.
- `static func run(config: GoodnightConfig, haConfig: HaConfig, now: Date) async -> GoodnightResult` — executes in order: (1) close configured garage covers (G1), (2) turn off lights = `lightsToTurnOff(all: <lights from /api/states>, keepOn: config.keepOnLights)` (G2), (3) lock `haConfig.lockId`, (4) arm `haConfig.entityId` with `resolveArmMode(...)` (G3, read panel Night support). CRITICAL: do NOT abort the sequence on a single step's failure — attempt ALL steps, collect per-step success/failure into `GoodnightResult`, so a lights-off failure never prevents the lock/arm. Each step best-effort; reuse existing runtimes (`AlarmActionRuntime`/`AlarmCommand` for lock+arm) + Task-3 helpers. Capture values before async; Swift 6 clean.
- [ ] A tested pure helper if any step-planning logic; then the runtime; app build SUCCEEDED; suite+gate → commit `feat(ios): Goodnight sequential runtime`.

### Task 5: RunGoodnightIntent (AppIntent, lock-screen)
**Files:** Create `Shared/RunGoodnightIntent.swift` (mirror an existing AppIntent e.g. `AlarmControlIntent`/`LightToggleIntent`).
- `struct RunGoodnightIntent: AppIntent { static var title …; static var openAppWhenRun: Bool { false } ; func perform() async throws -> some IntentResult }`: load `GoodnightStore`/`HaConfigStore`; if `!enabled` → `.result()`; if `!goodnightActive(now:…, .current calendar)` → return a result/dialog "Goodnight key is only active from <start> to <end>" (do NOT run); else `await GoodnightRuntime.run(...)`, then `WidgetCenter.shared.reloadAllTimelines()`.
- [ ] Implement; app+widget build SUCCEEDED; suite+gate → commit `feat(ios): Run Goodnight app intent`.

### Task 6: Goodnight settings page
**Files:** Create `Hearth/Settings/GoodnightPage.swift`; a tested subtitle/state mapper.
- Mock 23 (configured): enable toggle; a "one tap does" explainer row listing the 4 steps (icons); **When** group — Hours (a start/end hour picker or presets, default 9 PM–5 AM) + Arm mode (Night / Home, subtitle "Night (Home if unavailable)"); **Keep on at night** group — a lights multi-select (from configured lights) for `keepOnLights`. Explanatory content shows regardless of toggle (per the 5b lesson). Mock 23b (no alarm configured, i.e. `haConfig.entityId` empty): show "Uses the Home key on an Alarm widget" + an "Add Alarm" affordance instead of the config, no broken rows.
- Tested pure `goodnightPageState(hasAlarm: Bool, config:) -> GoodnightPageState` (e.g. `.noAlarm` / `.ready(summary)`).
- [ ] Failing tests for the state mapper (no-alarm → .noAlarm; configured → ready) → RED/GREEN; then the page + previews (on/off/no-alarm, light+dark); app sim build SUCCEEDED; suite+gate → commit `feat(ios): Goodnight settings page`.

### Task 7: Nav + DEBUG hook + parity + verify
**Files:** Modify `Hearth/Home/EveryDaySection.swift` (add a Goodnight row → `GoodnightPage`, mirror the Leave-by/Travel rows) + `Hearth/HearthApp.swift` (HearthSheet `.goodnight(UUID)` + `-goodnight` DEBUG hook, mirror `-leaveBy`); `docs/PARITY-AUDIT.md` ("## Goodnight key (Phase 5c)" — net-new; lock-screen App Intent not NFC; overnight window; no-abort sequence; G1/G2/G3 rulings; garage=Doors covers).
- [ ] Wire; app sim build SUCCEEDED; deep-link funnel intact; suite+gate → commit `feat(ios): wire Goodnight + parity note`.

## Notes
- Routines is a SEPARATE later sub-phase (needs a new action-history store); not in this plan.
- The overnight-window wrap and the no-abort sequence are the two correctness hotspots — their tests are mandatory.
- Reuse `AlarmActionRuntime`/`AlarmCommand` for lock+arm so Goodnight benefits from the same confirmation/safety behavior already shipped.
