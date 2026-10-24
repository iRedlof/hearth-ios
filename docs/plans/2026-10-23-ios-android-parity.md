# Hearth iOS — Android Parity Plan (Beacon widgets)

**Goal:** Bring the native iOS port to functional parity with the Android app for the
4 Beacon widgets — real **interactivity** (widget buttons that *do* things via
AppIntents) and the **Settings** needed to configure them — matching the Android
behaviour exactly where iOS/WidgetKit supports it, and deliberately omitting what it
cannot.

**Source of truth:** grounded inventory of `/Volumes/xHome/Github/hearth-cpauth`
(Android). Current iOS state: visuals + live Car read + HA OAuth sign-in all DONE and
verified on-device-sim (real data: "Stargate", 46%, Locked). Gap = interactivity +
settings + live data for Alarm/Thermostat/ChargePoint.

## Architecture facts (do not violate)
- **ONE global `HaConfig`** shared by every widget (already true on iOS). No per-widget
  HA config. Only per-widget setting is Card Style (not ported yet).
- All HA actions = `POST {baseUrl}/api/services/{domain}/{service}` with a JSON body
  containing `entity_id`. Auth via `HaAuth` access token (already built).
- **ChargePoint is NOT Home Assistant** — separate cloud, `coulomb_sess` cookie captured
  by a WebView login. Its auto-waitlist engine is **not portable** (see "iOS can't").
- No fake data, ever. Immutable updates (new `HaConfig` copies). Small files.

## iOS CANNOT do (omit by design — user approved "no point adding unsupported")
1. ChargePoint auto-waitlist engine (background polling, exact alarms, reading other
   apps' notifications). → Port only **manual** CP commands.
2. HA push-refresh broadcast. → Use WidgetKit timeline reloads.
3. **Biometric inside a widget tap.** → Gated actions (Disarm/Unlock) resolve via an
   AppIntent with `openAppWhenRun` → app does `LocalAuthentication` Face ID, then the
   service call. (Decision to confirm with user when we reach it.)
4. Debounced setpoint batching. → One `climate.set_temperature` per ± tap.
5. Lock-screen keyguard guard. → N/A (home-screen widgets only for now).
6. Install-detection for "Open Tesla"/"Open ChargePoint". → URL scheme deep links,
   graceful if app absent.
7. mDNS "Find on my network". → Defer (needs Local Network entitlement); manual URL +
   OAuth already covers setup.
8. Live countdown Chronometer (CP). → `Text(timerInterval:)` if/when CP detail ported.

## Per-widget action spec (the exact HA calls)

### Car — READ-ONLY (near done)
- No service calls. Only "Open Tesla" (deep link) + auto-refresh.
- iOS work: make the widget "Open Tesla" a `Link` to the Tesla URL scheme; whole-card
  tap opens Hearth. **Small.**

### Alarm — the rich one
State-dependent buttons (`actionsFor`): disarmed → ArmHome + ArmAway; armed/arming/
pending/triggered → Disarm; unknown → all three. Door button auto-labels Lock/Unlock.
- Arm home → `alarm_control_panel.alarm_arm_home` `{entity_id: entityId}` — **no confirm**
- Arm away → `alarm_control_panel.alarm_arm_away` `{entity_id: entityId}` — **no confirm**
- Disarm → `alarm_control_panel.alarm_disarm` `{entity_id: entityId}` — **GATED**
- Door Lock → `lock.lock` `{entity_id: lockId}` — **no confirm**
- Door Unlock → `lock.unlock` `{entity_id: lockId}` — **GATED**
- After a command, poll state until target appears ("Working…" / "No response").

### Thermostat
- Heat ± / Cool ± → `climate.set_temperature` (`target_temp_low`/`target_temp_high` for
  range; `temperature` for single mode). One call per tap (no debounce).
- Mode → picker (`s.modes`) → `climate.set_hvac_mode` `{hvac_mode}`
- Fan → picker (`s.fanModes`) → `climate.set_fan_mode` `{fan_mode}`
- Resume (only if `resumeId`) → `button.press` `{entity_id: resumeId}`
- `comfortId` is NOT wired to any control — do not build.

### ChargePoint (separate integration; manual only)
Commands (`CpCommand`): signin, location, join, leave, accept, snooze, unsnooze, start,
stop, still, done, open, (auto/stopauto = engine, OMIT). WebView login captures
`coulomb_sess`. Confirm = in-app sheet (not biometric). **Last** — biggest unknown.

## Settings surface (all GLOBAL)
Entity pickers query `GET /api/states`, filter by domain:
- Address (text, https) → `baseUrl`  [DONE via sign-in URL field]
- Sign in (OAuth) → `refreshToken`  [DONE]
- Long-lived token (secret text) → `token`
- **Alarm** picker `alarm_control_panel.` → `entityId`
- **Front door** picker `lock.` (+ None) → `lockId` + `lockName`
- **Disarm & unlock** segmented (biometric | dialog) → `confirmWith`
- **Thermostat** picker `climate.` (+ None) → `climateId`
- Room sensors multi (`sensor.` temp + `binary_sensor.` occupancy) → `sensorsJson`
- (Later / non-Beacon widgets) Doors, Scripts, Lights, Tiles → their JSON fields.

## Build order (vertical slices; each ends on the visible 18 Pro sim)
1. **Settings scaffold + Alarm entity picker** — a Settings screen reachable from the
   app; lists `alarm_control_panel.*` from `/api/states`; persists `entityId`. Unblocks
   Alarm. (HearthKit: entity-list parse + domain filter, TDD.)
2. **Alarm live + interactive** — AppIntents arm_home / arm_away / lock (ungated) first;
   then disarm / unlock (gated — confirm UX decision here). State-dependent buttons.
   Live timeline from `entityId`. Visible win: arm/disarm from the widget.
3. **Thermostat picker + live + interactive** — climate picker; setpoint ± / mode / fan
   / resume AppIntents; live timeline.
4. **Settings completion** — door-lock picker, confirm-mode segmented, room sensors,
   long-lived-token option.
5. **Car** — "Open Tesla" Link (small).
6. **ChargePoint** — WebView login + manual-command AppIntents (defer auto-engine).

## Verification per slice
HearthKit pure logic → `swift test` (TDD, macOS). Then build + install on the **visible**
iPhone 18 Pro (`8FC6C63B-9174-48DD-9C18-DB95DF359139`), screenshot, show the user.
Later: XCUITest flows to tap through combinations visibly. Commit per slice (no AI
attribution). Manual-only steps: user types HA password (done), user pins widget to home
screen.
