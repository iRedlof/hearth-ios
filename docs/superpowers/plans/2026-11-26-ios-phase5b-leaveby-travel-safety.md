# iOS Phase 5b — Leave-by · Travel days · Safety alerts Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development. Steps use checkbox (`- [ ]`).

**Goal:** Build three net-new, permission-gated "runs the house" features for iOS Hearth — **Leave-by** (calendar-aware pre-departure house check), **Travel days** (vacation-mode the night before a trip), and **Safety alerts** (notify when a close/lock/arm fails after one retry) — matching the approved Android mocks, on the Phase-1 design system.

**Architecture:** Net-new (NOT ports — no Android implementation exists; mocks only). All DECISION logic is pure and macOS-testable in HearthKit; the iOS frameworks (EventKit, UNUserNotifications, BGTaskScheduler) sit in thin wrappers behind injectable closure/protocol seams (mirroring Phase-5a's `fetchCommuteSensors(read:)`). Reuse `HaConfig` entities, `CpNotify`, the `AlarmCommand` action pattern, the design system, and the existing WidgetKit refresh.

**Tech Stack:** SwiftUI, EventKit, UserNotifications, BGTaskScheduler, Swift 6 strict concurrency, iOS 17+, Swift Testing + XCTest, XcodeGen, HearthKit.

**Spec:** design doc Phase 5; mocks `final-v2/22-leave-by-sheet`, `22b-leave-by-calendar-denied`, `22c-travel-days-sheet`, `22d-safety-alerts-notifications-off`. No Android source (planned-only).

## Global Constraints
- iOS 17; iPhone-only; Swift 6 `complete` concurrency. HearthKit decision code is PURE/`Sendable`/UIKit-free/macOS-testable — EventKit/UN/BGTask calls live only in app/Shared wrappers. **Controller verifies the APP-TARGET build itself** (the HearthKit suite passes even when the app target fails to compile).
- `xcodegen generate` + `git diff --exit-code` clean. App sim build `xcodebuild -sdk iphonesimulator CODE_SIGNING_ALLOWED=NO` must pass.
- Design tokens (HearthColor/HearthFont/HearthMetrics; HearthGroup/HearthRow/HearthSwitch/StatusPill) — no hardcoded style values. `@Dependency(\.date)`/no-`Date()`-in-logic; `Date.FormatStyle` not `DateFormatter`; dates computed in `TimeZone.current` (no UTC off-by-one).
- Permissions are EXPLICIT opt-in with denied-state handling (amber banner + Settings deep-link). No entitlements; Info.plist keys only.

## Rulings baked in (from research triage — see ledger for rationale/cost)
- **Q1** Leave-by checks reuse existing `HaConfig.entityId`(alarm)/`lockId`/`climateId`; no new entity pickers.
- **Q2** Travel vacation-mode = individual HA calls (alarm arm-away + climate setback) via existing paths; no new HA-script picker.
- **Q4 (owner-flagged)** Leave-by/Travel confirmation = notification → tap → **in-app confirm sheet** with explicit action buttons; nothing runs until confirmed.
- **Q5** Safety alerts monitor only configured entities (alarm `entityId`, lock `lockId`); garage/cover deferred (no `HaConfig` field); unconfigured → skipped gracefully.
- **Q6** retry interval 5s. **Q7** Travel notify 8 PM night-before, fixed.

## Review Focus
- **Nothing runs without confirmation:** a Leave-by/Travel notification must NEVER auto-arm/lock/setback — it only notifies; actions run only after explicit in-app confirm (Task 1/5 tests + review).
- **Permission-denied is honest + recoverable:** denied calendar/notifications → amber banner + working Settings deep-link, feature stays OFF; never a silent no-op or a crash (Task 2/3/5).
- **Safety alert fires once, after exactly one retry:** a transient failure retries once; only a confirmed final failure notifies; a network error (can't tell failure from unreachable) does NOT false-alarm (Task 4 tests).
- **Calendar scan is local-only + timezone-correct:** events read on-device; 8 PM-night-before and N-min-before times computed in `TimeZone.current`, not UTC (Task 1/2 tests).
- **Unconfigured entities degrade gracefully:** Safety/Leave-by skip entities not set in `HaConfig` rather than erroring (Task 1/4).

---

### Task 1: Leave-by decision logic + model (pure, tested)
**Files:** Create `HearthKit/Sources/HearthKit/LeaveBy.swift`; Test `LeaveByTests.swift`.
- `public struct LeaveByEvent: Sendable, Equatable { title: String; startDate: Date; location: String? }`
- `public struct LeaveByCheck: Sendable, Equatable { eventTitle: String; notifyAt: Date; checks: [LeaveByItem] }` where `LeaveByItem` enumerates the house checks derived from configured entities (alarm/lock/thermostat present in `HaConfig`).
- `public func leaveByChecks(events: [LeaveByEvent], minutesBefore: Int, now: Date, hasAlarm: Bool, hasLock: Bool, hasClimate: Bool) -> [LeaveByCheck]` — filter events with a non-empty location, startDate in the future, compute `notifyAt = startDate - minutesBefore·60` (only those with `notifyAt > now`), attach the checks for the configured entities. PURE.
- [ ] Failing tests: event with location in future → one check at the right notifyAt; event without location → excluded; past event / notifyAt already passed → excluded; minutesBefore options 10/15/20/30/45/60 compute correctly; timezone correctness; no configured entities → empty checks. RED→implement→GREEN→suite+gate→commit `feat(ios): Leave-by decision logic`.

### Task 2: EventKit wrapper + Travel-days scanner
**Files:** Create `Shared/CalendarAccess.swift` (EventKit wrapper, iOS 17 `requestFullAccessToEvents`, read events w/ location over next 7 days; injectable for tests); `HearthKit/.../Travel.swift` (pure `travelTrips`); Tests for the pure scanner.
- `travelTrips(events: [LeaveByEvent-or-TravelEvent], now: Date) -> [Trip]`: a trip = `isAllDay` OR duration ≥ 24h, starting within 7 days; compute `notifyAt = 8 PM the day before startDate` in `TimeZone.current`.
- `CalendarAccess`: `authorizationStatus()`, `requestAccess() async -> Bool` (iOS 17 full-access API), `upcomingEvents(days: Int) async -> [LeaveByEvent]` — thin, framework-only; a protocol or closure seam so Tasks 1/2 logic is tested without EventKit.
- [ ] Failing tests (pure `travelTrips`): all-day event → trip w/ notifyAt 8 PM prior day; 25h event → trip; 2h event → not a trip; trip >7 days out → excluded; 8 PM computed in local tz. RED→GREEN→suite+gate→commit `feat(ios): EventKit wrapper + Travel-days scanner`.

### Task 3: Notification scheduling + permission helpers
**Files:** Create `Shared/HouseNotify.swift` (or extend `Shared/CpNotify.swift`): schedule a `UNCalendarNotificationTrigger` at a date with a stable id; cancel by id; `authorizationStatus()` async; `requestPermission`. Injectable `schedule` seam for tests of the pure "which notifications" logic. Add an `authorizationStatus` read to support denied banners.
- [ ] A tested pure helper `plannedNotifications(checks:trips:) -> [PlannedNotification{id,title,body,fireAt}]` (dedupe by id; stable ids `leaveby-<event>` / `travel-<event>`); then the scheduling wrapper. RED→GREEN→suite+gate→commit `feat(ios): house notification scheduling`.

### Task 4: Safety-alerts retry monitor
**Files:** Create `HearthKit/.../SafetyMonitor.swift`; Test `SafetyMonitorTests.swift`.
- `public protocol ActionExecutor: Sendable { func execute() async throws; func verify() async throws -> Bool }` and `public func monitorWithRetry(_ action: ActionExecutor, retryDelay: Duration = .seconds(5), onFinalFailure: @Sendable () -> Void) async` — execute → wait → verify; if not verified, retry once → wait → verify; only if STILL not verified call `onFinalFailure`; a thrown error (network/unreachable) must NOT call `onFinalFailure` (can't distinguish failure from unreachable). Make the delay/sleep injectable so tests are instant.
- Define which actions map to executors (alarm arm via `entityId`, lock via `lockId`; garage deferred). Skip unconfigured.
- [ ] Failing tests with a mock `ActionExecutor`: succeeds first try → no notify; fails then retry-succeeds → no notify; fails both → notify once; throws → no notify. RED→GREEN→suite+gate→commit `feat(ios): safety-alert retry monitor`.

### Task 5: Settings sheets (Leave-by / Travel / Safety)
**Files:** Create `Hearth/Settings/LeaveByPage.swift`, `TravelDaysPage.swift`, `SafetyAlertsPage.swift`; a tested status mapper for the denied/next-trip subtitles.
- Match mocks 22/22b/22c/22d + design tokens: Leave-by (switch, minutes-before chips 10–60, privacy line, calendar-denied amber banner + Allow→Settings); Travel (switch, "Next: <trip> · <day>", description, privacy line, denied banner); Safety (switch, notifications-off amber banner + "Turn on"→Settings, the shield/retry explainer rows). Persist enable flags to an App-Group store (new `Shared/HouseFeaturesStore.swift` or extend an existing one). The confirm sheet (Q4) that a tapped notification opens — the explicit arm/lock/Eco confirm UI — lives here too.
- [ ] Failing tests for the pure subtitle/status mappers (denied→banner state; next-trip label) → RED/GREEN; then the three pages + previews (on/off/denied, light+dark); app sim build SUCCEEDED (controller-verified); suite+gate→commit `feat(ios): Leave-by/Travel/Safety settings pages`.

### Task 6: Background calendar scan + Info.plist
**Files:** Modify `Hearth/Info.plist` (add `NSCalendarsUsageDescription`, `UIBackgroundModes` [fetch, processing], `BGTaskSchedulerPermittedIdentifiers` for the leaveby/travel scan ids) + `project.yml` if it owns Info.plist keys; a small app-level scheduler that, on launch + on the existing refresh cadence, scans the calendar (if authorized + feature enabled) and (re)schedules the planned notifications. Reuse the WidgetKit refresh or a single `BGAppRefreshTask`.
- [ ] Wire the scheduler to call Task-2 `upcomingEvents` → Task-1/2 logic → Task-3 scheduling; app sim build SUCCEEDED; xcodegen/gate clean; suite+gate→commit `feat(ios): background calendar scan + Info.plist`.

### Task 7: Safety-alert hook + nav wiring + DEBUG hooks + verify/parity
**Files:** Modify the alarm/lock action execution path to run `monitorWithRetry` (via `ActionExecutor` wrappers) when Safety alerts enabled; Home rows (`Hearth/Home/*`) + Settings route to the three sheets; add DEBUG hooks `-leaveBy`/`-travelDays`/`-safetyAlerts`; update `docs/PARITY-AUDIT.md` ("## Leave-by / Travel / Safety (Phase 5b)" incl. the net-new status, the no-auto-action guarantee, and the owner-flagged confirm-UX ruling).
- [ ] Wire; app sim build SUCCEEDED; deep-link funnel intact; suite+gate→commit `feat(ios): wire house features + parity note`.

## Notes
- These are net-new builds; favor the mocks' copy verbatim. Keep every framework call behind a seam so logic stays macOS-tested.
- Safety alerts "always fire" (not a routine toggle) per the design — but still gated by the master Safety switch + notification permission.
- Garage/cover monitoring deferred (no `HaConfig` field); record in the parity note.
