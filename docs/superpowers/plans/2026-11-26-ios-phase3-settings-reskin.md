# iOS Phase 3 — Settings re-skin (HA + ChargePoint + Alerts) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Re-skin the Home Assistant and ChargePoint settings surfaces from stock `Form`/`Section`/`LabeledContent`/`Toggle` into the Android-v2 look — status-first pushed pages with a "split hero" card and `HearthGroup`/`HearthRow`/`HearthSwitch`/`StatusPill` cards — reachable from the Home Connections rows and the Settings tab. All underlying logic (SettingsRuntime, HaConfigStore, CpSessionStore) is reused unchanged.

**Architecture:** New SwiftUI pages in `Hearth/Settings/` (HomeAssistantPage, ChargePointPage, ChargePointAlertsPage) + sub-sheets. A reusable `ConnectionHero` component (status panel + content/CTA panel) in HearthKit with a pure, tested status→presentation mapping. Pages wrap the EXISTING write paths: `SettingsRuntime.saveHaEdit`/`performCpEdit`, `HaConfigStore`, `CpSessionStore`. Presented as pushed pages in a `NavigationStack`; the ContentView TabView + deep-link/sheet/gate infra stays intact (as in Phase 2).

**Tech Stack:** SwiftUI, Swift 6, iOS 17+, Swift Testing, XcodeGen, HearthKit.

**Spec:** `docs/superpowers/specs/2026-11-26-ios-android-parity-port-design.md` (Phase 3); target mocks `hearth-task-artifacts/hearth-settings/final-v2/` 05/05b/05c/06/06b/07/07b (HA), 08/08b/08c/08d/08e (CP), 09/09b (alerts).

## Global Constraints

- iOS 17; iPhone-only. Swift Testing only; HearthKit tests `cd HearthKit && swift test` (macOS — no UIColor in model code).
- `xcodegen generate` output in sync (CI `git diff --exit-code`). App must build for simulator (`xcodebuild -sdk iphonesimulator CODE_SIGNING_ALLOWED=NO`).
- All styling via the design system (HearthColor/HearthFont/HearthMetrics/HearthGroup/HearthRow/HearthSwitch/StatusPill/IconTile/InkButtonStyle); no ad-hoc colors. (Spacing-literal extraction remains a Phase-6 item — don't block on it, but prefer existing tokens.)
- **Reuse existing logic only** — do NOT change `SettingsRuntime`, `HaConfigStore`, `CpSessionStore`, `HaSettingsSections`' write semantics, or the CP edit actions. Re-skin the containers/rows and route to the same setters.
- Keep the ContentView TabView + `.sheet(item:)`/gates/`onOpenURL` intact.
- Keep copy from the mocks where shown (e.g. "Renews by itself", "Join the work charger line").

## Review Focus

- **Expired HA token:** the HA page hero shows "Needs sign-in" (amber) with a working "Sign in again" that re-runs the real OAuth flow — pinned in Task 2.
- **Auto-waitlist OFF on ChargePoint:** the Morning-commute / car's-plug rows correctly disable and the Alerts summary reflects "need Auto-waitlist" — pinned in Task 3/Task 4.
- **Sign-out confirmation:** HA/CP sign-out asks first (destructive) and actually calls the existing sign-out edit — pinned in Task 2/Task 3.
- **Not-set-up ChargePoint:** the page shows the 2-step setup (sign in → pick place), not a broken/empty page — pinned in Task 3.
- **Entity selections still reachable:** re-skinning the HA page to be connection-focused must not lose access to the alarm/thermostat/lights/etc. pickers (they stay in the Settings-tab `HaSettingsSections` or move to the HA page's "Devices" area — Task 2 keeps them reachable).

---

### Task 1: `ConnectionHero` component + status presentation mapping

**Files:** Create `HearthKit/Sources/HearthKit/Settings/ConnectionHero.swift`; Test `HearthKit/Tests/HearthKitTests/ConnectionHeroTests.swift`.

**Interfaces — Produces:**
- `public struct HeroPresentation: Sendable, Equatable { public let tone: StatusTone; public let word: String; public let icon: String }` and pure mappers `public func haHeroPresentation(_ s: HaConnectionStatus) -> HeroPresentation` (connected→(.ok,"Connected","checkmark.circle.fill"), needsSignIn→(.warn,"Needs sign-in","lock.fill"), notSetUp→(.neutral,"Not set up","house.fill")) and `public func cpHeroPresentation(_ s: CpConnectionStatus) -> HeroPresentation` (analogous, icons bolt.car.fill etc.). Add an `.offline` concept: `public func haHeroOffline() -> HeroPresentation` (.neutral,"Offline","cloud.slash") for the check-connection failure state.
- `public struct ConnectionHero<Side: View>: View` — `init(title: String, status word via `HeroPresentation`, detail: String, @ViewBuilder side: () -> Side)`: the split card — left panel tinted by tone (`HearthColor.greenBg/amberBg/tint`) with icon + big word (`HearthFont.cardHeading`) + detail (`HearthFont.subtitle`), right/under panel (`HearthColor.ink` dark) hosting the `side` CTA. Corner `HearthMetrics.groupRadius`.

- [ ] Step 1: failing test `ConnectionHeroTests` — assert the pure mappers (haHeroPresentation/cpHeroPresentation for all 3 statuses → correct tone+word; offline → .neutral "Offline"). Raw/value asserts only (StatusTone + strings), macOS-safe.
- [ ] Step 2: `cd HearthKit && swift test --filter ConnectionHeroTests` → FAIL.
- [ ] Step 3: implement the mappers + the `ConnectionHero` view (with light+dark `#Preview` across tones). Step 4: test PASS. Step 5: full `swift test` + app sim build + `xcodegen generate`/`git diff` clean. Step 6: commit `feat(ios): ConnectionHero + status presentation`.

---

### Task 2: Home Assistant page

**Files:** Create `Hearth/Settings/HomeAssistantPage.swift` (+ sub-sheets `AddressSheet`, `SignInExplainerSheet` or fold into the file); Modify nav in Task 6.

**Interfaces — Consumes:** Task 1 `ConnectionHero`, `HaConnectionStatus`/`haConnectionStatus`, `SignInView` (existing OAuth), `SettingsRuntime`, `HaConfig`/`HaConfigStore`, the existing entity pickers.
**Produces:** `struct HomeAssistantPage: View` (`init(config:runtime:onChange:)`): a `ScrollView` over `HearthColor.page`: the `ConnectionHero` (title = place/host, status from `haConnectionStatus`, detail = device/widget counts if available else host, side CTA = "Check connection" when connected / "Sign in again" when needsSignIn / "Connect" when notSetUp) with a **Check-connection action** that runs the existing HA discover/ping (via `runtime.discoverHa(..., purpose:)`) and reflects OK (transient green) or Offline (`haHeroOffline()`); a `HearthGroup` with **Web address** row (→ `AddressSheet` prefilled from `config.baseUrl`, Save → the existing connect/edit path) and **Sign-in** row (→ `SignInExplainerSheet`: "Renews by itself" + "Use an access token" + a destructive **Sign out** that shows a confirm `.alert` then calls the existing `signOutHa` edit); and a **Devices** `HearthGroup` that routes to the existing entity pickers (Alarm/Thermostat/Lights/etc. — reuse `HaSettingsSections`' rows/pickers, re-skinned as `HearthRow`s, so entity selection stays reachable).

- [ ] Step 1: failing test — a pure helper `func haHeroDetail(host: String, deviceCount: Int?, widgetCount: Int?) -> String` in HearthKit (`Settings/HaHeroText.swift`) producing the hero detail string ("home.example.net" / "42 devices · 4 widgets"); test it.
- [ ] Step 2: FAIL → Step 3: implement the helper + the page wiring the existing setters + the check-connection action + sheets + sign-out confirm; `#Preview`s for connected/needsSignIn/notSetUp/offline, light+dark. Step 4: test PASS. Step 5: full `swift test` + app sim build + gate clean. Step 6: commit `feat(ios): Home Assistant settings page`.

---

### Task 3: ChargePoint page

**Files:** Create `Hearth/Settings/ChargePointPage.swift` (+ `FasterOffersSheet`).

**Interfaces — Consumes:** Task 1, `CpConnectionStatus`/`cpConnectionStatus`, `CpSettingsSection`'s existing logic/edits (`SettingsRuntime.performCpEdit`, `SettingsCpState`, `SettingsCpEdit`), `CpSessionStore`, existing `CpSignInView`/`CpLocationSearchView`.
**Produces:** `struct ChargePointPage: View`: `ConnectionHero` (status from signed-in/account; detail = place / plugs-free / sign-in-good-for when available); **Account** `HearthGroup` (Place row → existing `CpLocationSearchView`; Sign-in row → existing `CpSignInView` / "Good for …" caption); **Waitlist** `HearthGroup` (Auto-waitlist `HearthSwitch` → the existing `.auto(.join/.resume/.pause)` edit with the same enable/disable logic; a Morning-commute `HearthRow` → `.settings` placeholder for Phase 5 with a TODO; "Car's plug holds snooze" toggle; "Faster offers" row → `FasterOffersSheet`); **Alerts** summary `HearthRow` → push `ChargePointAlertsPage` (Task 4); **Widget** row. When signed out: the 2-step "Set up" card (Sign in → Pick place), matching `08b`. When Auto OFF: the commute/car's-plug rows disabled with "Turn on Auto-waitlist first" (`08d`).

- [ ] Step 1: failing test — pure helper `func cpHeroDetail(place: String?, plugsFree: Int?, plugsTotal: Int?, signInMinutesLeft: Int?) -> String` (HearthKit `Settings/CpHeroText.swift`); test it ("Office · 2 of 4 plugs free" / "Not set up").
- [ ] Step 2–4: FAIL → implement the helper + page wiring the existing CP edits (no logic change) + signed-out setup card + auto-off disabling + faster-offers sheet; `#Preview`s connected/needs-sign-in/not-set-up/auto-off, light+dark → PASS. Step 5: full `swift test` + app sim build + gate clean. Step 6: commit `feat(ios): ChargePoint settings page`.

---

### Task 4: ChargePoint Alerts page

**Files:** Create `Hearth/Settings/ChargePointAlertsPage.swift`.

**Interfaces — Consumes:** the existing CP alert edits (`.alert("offer"/"accepted"/"snoozed"/"second", on)` via `performCpEdit`), `SettingsCpState`'s alert flags, `cpConnectionStatus`/auto state.
**Produces:** `struct ChargePointAlertsPage: View`: title "Alerts"; **"Every charge"** `HearthGroup` (Your turn, Done charging switches); **"While Auto runs"** `HearthGroup` (Accepted & held, Snoozed, Second offer switches) — dimmed/disabled when Auto is off (`09b`), with the "Turn on Auto-waitlist" caption; **"Always sent"** static `HearthGroup` (Drive now / Move your car / Failed action / Signed out, informational IconTile rows) + the "at most 2 reminders…" caption. Each switch wired to the existing alert edit; the dim-when-auto-off state matches `08d`/`09b`.

- [ ] Step 1: failing test — pure helper `func whileAutoRunsEnabled(autoOn: Bool) -> Bool` + the alert-key→edit-name mapping (so the toggles call the right edit) as a tested pure function `cpAlertEditName(for:) -> String`; test both.
- [ ] Step 2–4: FAIL → implement helper + page with switches wired to existing edits + auto-off dimming + the always-sent list; `#Preview` auto-on and auto-off, light+dark → PASS. Step 5: full `swift test` + app sim build + gate clean. Step 6: commit `feat(ios): ChargePoint alerts page`.

---

### Task 5: Sub-sheets & confirmations polish pass

**Files:** the sheet views created in Tasks 2–4 (`AddressSheet`, `SignInExplainerSheet`, `FasterOffersSheet`) — ensure they match mocks 05c/07/07b/08e; create any still missing.

**Interfaces — Produces:** themed bottom-sheet views matching the mocks (title + explainer rows + Cancel/primary buttons via `InkButtonStyle`), the HA sign-out confirm `.alert` (07b), and the CP sign-out confirm. Each wired to the existing edits.

- [ ] Steps: build/refine the sheets with `#Preview`s (light+dark). No new logic tests (actions already tested/existing); verify via app sim build + the Task 7 screenshots. Commit `feat(ios): settings sub-sheets + confirmations`.

(If Tasks 2–4 already produced complete sheets, fold this into them and make Task 5 a no-op/skip — the controller may drop it.)

---

### Task 6: Navigation wiring

**Files:** Modify `Hearth/HearthApp.swift` (`handleHomeRoute` + the `.sheet(item:)`/presentation), and `Hearth/SettingsView.swift` (link to the new pages).

**Interfaces — Produces:** `.homeAssistant` from Home now pushes/presents `HomeAssistantPage` (not just `selection = 1`); `.chargePoint` presents `ChargePointPage` (replacing the bare sign-in/location sheet as the entry, which the page then pushes into). From the Settings tab, the HA and ChargePoint rows open the same pages. Keep the TabView, existing gates, `onOpenURL`, and the raw `CpSignInView`/`CpLocationSearchView`/`SignInView` (now reached THROUGH the pages). Present pages in a `NavigationStack` (sheet or pushed — match the Phase-2 pattern; a sheet-hosted NavigationStack is fine).

- [ ] Step 1: a pure routing test if any logic is extractable (else none). Step 2–4: implement the wiring; confirm deep links still work (the `hearth://` funnel + gates untouched). Step 5: app sim build + full `swift test` + gate clean. Step 6: commit `feat(ios): route Home/Settings to the new HA & ChargePoint pages`.

---

### Task 7: Verify against mocks + parity note

**Files:** none + `docs/PARITY-AUDIT.md`.

- [ ] Step 1: add DEBUG `-haPage`/`-cpPage`/`-cpAlerts` launch hooks (like `-homePreview`) rendering each page with a fixture, behind `#if DEBUG`, no release-path change.
- [ ] Step 2: boot ONE simulator, screenshot HA page (connected/needs-sign-in), CP page (connected/not-set-up/auto-off), Alerts (auto-on/off) → `/tmp/ds-settings-*.png`. Compare to the `final-v2` mocks; note gaps.
- [ ] Step 3: shut down sim; update `docs/PARITY-AUDIT.md` ("## Settings (Phase 3)"). Commit `chore(ios): Phase 3 settings parity note + preview hooks`.

---

## Notes for later phases
- Entity pickers remain functional (re-skinned on the HA page or kept in the Settings tab); per-widget settings pages are Phase 4.
- Morning-commute row routes to a placeholder until Phase 5 builds the commute feature.
- The full tab-shell→NavigationStack collapse is still deferred; Phase 3 presents the new pages via sheets/push without removing the TabView.
