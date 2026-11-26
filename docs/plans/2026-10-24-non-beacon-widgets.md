# Non-Beacon Widgets — iOS Parity Plan

Port the 6 non-Beacon Android widgets to iOS/WidgetKit. Grounded in the Android source
(`/Volumes/xHome/Github/hearth-cpauth`). Build AFTER ChargePoint (shares SettingsView /
HearthWidgetBundle / LiveDashboard / project.yml).

## iOS family mapping (Android has NO small/med/large — free resize, SizeMode.Exact)
- 5 "tall" widgets (Doors, Lights, Favourites, Activity, Batteries): target 4×3 → **`.systemLarge`**
  (collapse rows for a `.systemMedium` variant). Android "narrow" breakpoint innerWidth<300dp; grid
  columns 2(<240)/3(<400)/4(≥400).
- **Quick**: 4×2, width-only resize → **`.systemMedium`**.

## Shared prerequisites (build once, in HearthKit unless noted)
- **HA reads** on `HaClient`: `callService` (have). ADD: `statesJson(ids)` batch via one `/api/template`
  (fallback per-entity GET on 400); `logbookJson(sinceISO, ids)` = `GET /api/logbook/<ISO>?entity=csv`;
  `template(tpl)` (have). `allStatesJson` (have).
- **Templates**: `LIGHTS_TEMPLATE` (states.light → id/state/name/brightness/since/group/rgb; drop groups,
  LED segments, offline), `BATTERY_TEMPLATE` (states.sensor device_class=battery, unit %, numeric; exclude
  self-charging integrations: mobile_app, tesla_*, teslemetry, tessie, roborock, powerwall). Copy verbatim
  from Android `LightsState.kt` / `BatteryState.kt`.
- **Card chrome** (Shared SwiftUI): a `CardFrame` equivalent + card-tone system (green/amber/red/grey per
  widget) + "Checked HH:MM" stamp + ↻. The Beacon cards already establish the look; generalise.
- **Optimistic-command-then-verify** state machine (core, reproduce on iOS): on tap set busy "<kind>:<id>",
  show "Working…/Opening…/Turning on…", call service, then reload timeline; next fetch confirms against real
  HA state; on error show "Failed/No response". Never fake success. (On a widget, "poll" = schedule a prompt
  timeline reload; the provider re-reads HA.)
- **Gating decision (iOS)**: WidgetKit has no home-vs-lockscreen tap split. Android runs the "safe" set
  (Close/Lock/Stop/TurnOff/Refresh/Arm) unconfirmed on the home screen and gates the "risky" set
  (TurnOn/RunScript/toggle-on/Unlock/Disarm/garage-Open) only on the lock screen. iOS plan: ungated taps for
  all EXCEPT **garage Open**, which ALWAYS confirms via Face ID (reuse `AlarmGate` pattern → `openAppWhenRun`
  → LocalAuthentication, dialog fallback). Match Android's `confirmWith`. (Lock-screen accessory widgets are
  out of scope for now.)

## Widgets (build order by complexity)

1. **Batteries** — READ-ONLY. All battery sensors live via BATTERY_TEMPLATE; no config. Rows lowest-first:
   name + level bar (hide when narrow) + NN% (amber ≤30, red ≤10). Tone green/amber/red. Only ↻. No picker.
   Refresh **hourly** (timeline policy .after(1h)). Simplest → do first as scaffolding.
2. **Activity** — READ-ONLY. HA logbook last 24h for: alarm (`entityId`) + lock (`lockId`) + doors
   (`doorIds` or auto) + car lock & charge cable (via CAR_TEMPLATE, cache 1 day). Dedupe repeats, drop
   in-between steps + restart-stamped + garage echoes (port `activityFrom` from `ActivityState.kt`). Rows:
   time + kind icon + text ("Garage closed") + optional "by <context>". Only ↻. No picker (static desc).
3. **Lights** — INTERACTIVE (uniform). All lights live via LIGHTS_TEMPLATE (drop groups/segments/offline).
   `lightPinsJson` = "always show" pinned set (NOT the list). Tile grid 2/3/4 cols, two sections (on-lights,
   then "── ALWAYS SHOW ──" divider, then pinned). Tile: rgb-tinted bulb + % + name + since/Off. Tap →
   `light.turn_on`/`turn_off` AppIntent (verify). "+N more" → companion full-list (app screen or deep link;
   iOS can't grow a widget). Settings: multi-pick "Always show" → `lightPinsJson`.
4. **Quick** — INTERACTIVE (one action). `scriptIds` (auto-discover: scripts run last 60d, not shortcut/
   security, max 6). Keys grid 2/row ≤6. Tap → `script.turn_on` AppIntent, confirm via `last_triggered`
   advancing. `.systemMedium` only. Settings: multi-pick ordered "Scripts" (exclude security arm|disarm|
   unlock|alarm + shortcut names) → `scriptIdsJson`.
5. **Favourites** — INTERACTIVE (5 domains). `favouriteIds` ordered ≤12, domains switch/light/fan/
   input_boolean/script. Tile grid (reuse Lights'). Tap → `favServiceFor`: script→`script.turn_on`; else
   `<domain>.turn_on/off` (opposite of current). Verify. Settings: multi-pick ordered ≤12 → `favouriteIdsJson`.
6. **Doors** — INTERACTIVE, most complex. `doorIds` (auto: cover garage/gate + binary_sensor door/garage_door
   + `lockId`). Rows open-first: icon + name + status ("Open · 3 min"/"Locked") + action. Actions:
   Close→`cover.close_cover`, Open→**ConfirmActivity gate** (`cover.open_cover`, always Face ID), Stop→
   `cover.stop_cover`, Lock→`lock.lock`. Sensors read-only. Tone green/amber/**red if open ≥30 min**.
   Settings: multi-pick "Doors" (door/window/garage covers + non-group locks, garage-first) → `doorIdsJson`.

## Per widget: new WidgetKit widget (kind `com.rohit.hearth.<x>`) in HearthWidgetBundle + Provider (live
## fetch mirror AlarmProvider) + Shared SwiftUI card + (interactive) AppIntents in Shared/ + Settings section
## + LiveDashboard card. TDD the pure parse/logbook-dedupe/grid-column math in HearthKit.
