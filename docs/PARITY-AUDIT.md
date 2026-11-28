# Hearth iOS ↔ Android Parity Audit (living gate)

**THE RULE (binding on the assistant, not the user):** The Android app at
`/Volumes/xHome/Github/hearth` is the approved spec. Before handing ANY work back:
1. For every widget/screen, diff the iOS build against the Android source — **layout
   proportions, every state, every interaction, every setting, every string** — and against
   a live Simulator screenshot.
2. If any row below is not `✅ parity`, it is a gap. Fix it, rebuild, re-verify. Do NOT hand
   back with an open gap. The loop closes here, by me, not by the user finding it.
3. "Verify" = (a) Android source ref cited, (b) iOS code matches it, (c) Simulator screenshot
   confirms the render. All three, or it's not done.

Status key: `✅ parity` · `⚠️ partial` · `❌ gap` · `🔍 auditing` · `🚧 fixing`

---

## A. Cross-cutting (every widget)

| # | Item | Android spec (ref) | iOS status | Notes |
|---|------|--------------------|-----------|-------|
| A1 | Beacon left/right split ratio | `BeaconMetrics.kt` railDp=130/352≈36.9% | ✅ parity | FIXED: `beaconSplit()` ports Android railDp math (4 tests); hero verified ~37% on Simulator (was 50/50). |
| A2 | App name label under widget on Home Screen | n/a | ⚠️ iOS platform wall | NOT code-removable. iPhone draws the app's display name under EVERY Home-Screen widget; no WidgetKit API changes it (verified: we draw no "Hearth" text; containerBackground already adopted). User-side only: iOS 18+ Home Screen → Edit → Customize → **Large** hides all labels; iPad never shows them. Documented, not a code gap. |
| A3 | Refresh button: animation + immediate update | Android updates on tap | ✅ improved (+⚠️ wall) | Added `invalidatableContent` → the freshness stamp shows the system "updating" redaction from tap until fresh data lands (the sanctioned feedback). A spinning button is an iOS wall (static snapshots, 2s cap, no continuous animation). Refresh DOES update — reload re-fetches HA; the "Checked HH:MM" changes; latency = network. |
| A4 | Widget buttons act in place (no app launch) | Glance actionRunCallback (in place) | ✅ parity | All 14 intents now run in the widget process; 0 `openAppWhenRun`. |
| A5 | Card outer margins / corner treatment | 🔍 | ⚠️ partial | WidgetKit fixes corner radius (documented wall); verify margins. |

## B. Per-widget (layout · states · interactions · copy)

Side-by-side (iOS Simulator vs Android design renders): **`docs/parity-comparison/index.html`**.

| Widget | Layout | Interactions | Overall | Concrete gaps found (vs Android design render) |
|--------|--------|--------------|---------|-----------------------------------------------|
| Thermostat | ✅ | ✅ | ✅ near parity | ~ "Resume" vs Android "Back to Schedule"; "Checked" vs "Last check" |
| Alarm | ⚠️ | ✅ | ⚠️ gaps | ❌ no "Unlock" button in the Front Door well; ❌ Arm buttons lack house/shield icons; ~ "Locked" is plain text not a green pill |
| Car | ❌ | ✅ | ⚠️ arrangement gaps | ❌ Lock/Doors should be fact chips in the RIGHT panel (Android), not hero rows; ❌ missing "Not plugged in / Charge limit 80%" line; ~ Open-Tesla full-width vs half-width beside chips |
| ChargePoint | ❌ | ✅ | ❌ biggest gaps | ❌ hero should lead with the big countdown clock + "to accept" (iOS leads with "Your turn"); ❌ right body should show "go to level P3 / SEA41-29"; ❌ no floor-level stats (P2–P6 counts); ❌ missing per-state body variants |
| Battery | 🔍 | n/a (read-only) | 🔍 | not yet diffed |
| Activity | 🔍 | n/a (read-only) | 🔍 | not yet diffed |
| Lights | 🔍 | 🔍 | 🔍 | not yet diffed |
| Quick | 🔍 | 🔍 | 🔍 | not yet diffed |
| Favourites | 🔍 | 🔍 | 🔍 | not yet diffed |
| Doors | — | — | — | removed on iOS (owner decision 2026-11-28); the garage is a row on the Alarm card |

**Cross-cutting copy gap:** Android freshness stamp reads **"Last check"**; iOS reads **"Checked"** (all beacon widgets).

## C. Settings parity
| Item | Status |
|------|--------|
| Entity rows show friendly names | ✅ parity |
| ChargePoint section (account/location/name/auto/alerts/sign-out) | ✅ parity |
| All pickers present (alarm/lock/garage/confirm/climate/resume/sensors/lights/scripts/fav/doors) | 🔍 |

## D. Auto-engine (ChargePoint)
| Item | Status |
|------|--------|
| cpAutoDecide ported 1:1 (12 tests) | ✅ parity |
| All 8 alerts gated as Android | ✅ parity |

---

## iOS design system (Phase 1)

**Foundation tokens and components built:**

- **Tokens:** HearthColor (warm palette, light+dark ARGB), HearthFont (Roboto Flex variable type ramp), HearthMetrics (spacing/sizing constants)
- **Components:**
  - `StatusPill` — ok/warn/neutral status chips with leading dot
  - `IconTile` — 7-hue SF Symbol tiles (blue/orange/purple/green/red/amber/neutral)
  - `HearthSwitch` — custom toggle aligned with design system
  - `InkButtonStyle` / `InlineRowButtonStyle` — accent and inline action buttons
  - `HearthGroup` — labeled card container with auto-dividers between rows
  - `HearthRow` — icon+title+subtitle+trailing setting rows

**Phase 1 complete:** All foundation components verified in `DesignSystemGallery.swift` (DEBUG-only, light+dark screenshots captured at `/tmp/ds-gallery-{light,dark}.png`).

---

## Home dashboard (Phase 2)

**Status:** ✅ Shipped (replaces Live tab)

**Components built:**
- `HomeView` — main dashboard assembler, fetches live snapshots (car/alarm/CP/thermostat) and maps to widget health
- `HomeHeader` — "Hearth" title header
- `YourWidgetsStrip` — horizontal scrolling widget cards with health indicators (ok/warn/error/stale), problems-first sorting
- `GetStartedCard` — 2-step first-run onboarding (Connect HA → Add widget)
- `SignInBanner` — contextual sign-in prompt when connection lost
- `ConnectionsSection` — HA and ChargePoint connection status rows
- `EveryDaySection` — 5 feature rows (Goodnight/Routines/Leave-by/Travel/Safety) with descriptive subtitles
- `LookSection` — Card style customization row
- `HomeFooter` — version + "Up to date" / update CTA

**States implemented:**
- Populated: widgets strip with live data, all sections visible
- First-run: Get-started card replaces widgets, connections show "Not set up"
- Needs sign-in: Sign-in banner shown when HA/CP needs re-auth
- Dark mode: full dark theme support
- Large text: accessibility text scaling (tested with `.accessibilityExtraLarge`)
- Offline/stale: health badges show "Stale data" / "Error" states

**Navigation:**
- TabView retained (3 tabs: Live/Settings/Preview) — full nav collapse deferred to Phase 3/4
- Every-day feature rows route to Settings tab (Phase 5 builds real destinations)
- Widget taps route to Settings (Phase 4 builds widget detail pages)
- Deep links still work via TabView funnel (smoke-checked: `hearth://car-readings/unavailable`)

**DEBUG hooks:** `-homePreview` (populated), `-homePreviewFirstRun` render HomeView states without signing in.

**Screenshots:** `/tmp/ds-home-{light,dark,firstrun}.png` captured from iPhone 18 Pro simulator.

**Gaps vs Android Home mocks:**
- Widgets strip shows health states but not fully populated widget data in fixture (live HomeView fetches real snapshots)
- Footer lacks "Check for updates" button animation (static button, update state from live data)
- Phase 3/4 nav collapse will replace TabView with NavigationStack + push destinations

---

## Settings (Phase 3)

**Status:** ✅ Shipped (HomeAssistantPage, ChargePointPage, ChargePointAlertsPage)

**Components built:**
- `HomeAssistantPage` — HA settings page with ConnectionHero, connection details, device entity pickers
- `ChargePointPage` — CP settings page with ConnectionHero, account/location/auto/alerts sections
- `ChargePointAlertsPage` — Dedicated alerts page with grouped toggles (Every charge / While Auto runs / Always sent)
- `ConnectionHero` — Reusable status-first hero (connected/needs-sign-in/not-set-up with green/amber/neutral pills)

**States implemented:**
- HA connected: Shows ConnectionHero with green checkmark, web address, sign-in row, device entity pickers
- HA needs sign-in: Shows ConnectionHero with neutral house icon, "Connect" CTA, connection rows only
- CP connected: Shows ConnectionHero with green checkmark, account/waitlist/alerts/widget groups
- CP not set up: Shows ConnectionHero with neutral car icon, "Set up in 2 steps" card with sign-in/location buttons
- Alerts page (auto on): All toggles enabled, shows "In the order a charge happens" caption
- Alerts page (auto off): "While Auto runs" group disabled with explanatory footer

**Integration:**
- Reuses existing logic from SettingsRuntime, HaConfigStore, CpSessionStore
- Presents via HearthSheet cases (.homeAssistantPage, .chargePointPage) in ContentView
- TabView navigation retained (Phase 3/4 nav collapse deferred)
- Entity pickers (alarm/lock/climate/resume/sensors) functional on HA page
- CP alerts route correctly from ChargePointPage → ChargePointAlertsPage

**DEBUG hooks:** `-haPage`, `-haPageNeedsSignIn`, `-cpPage`, `-cpPageNotSetUp`, `-cpAlerts` render each page state with fixtures.

**Screenshots:** `/tmp/ds-{ha,ha-signin,cp,cp-setup,cp-alerts}.png` captured from iPhone 18 Pro simulator.

**Parity vs Android mocks:**
- ConnectionHero matches Android status-first design (green/amber/neutral pills, icon+title+detail layout)
- HA page device list matches Android entity rows with icons
- CP page groups (Account/Waitlist/Alerts/Widget) match Android structure
- Alerts page grouped sections ("Every charge", "While Auto runs", "Always sent") match Android grouping
- Minor: iOS uses native NavigationStack toolbar vs Android top bar, iOS switches vs Android checkboxes

---

## Widgets (Phase 4)

**Status:** ✅ Shipped (Add-a-widget gallery, per-widget settings pages, Card style page)

**9 widgets, one size each, all medium.** Every widget is a Beacon card: a rail with the answer
and a body with the details. Lights, Quick actions, Favourites, Activity and Battery became
two-panel cards on 2026-11-28 (Lights, Favourites and Activity were large before); see
`docs/CARD-STYLE-IOS.md`, "Two-panel widgets".
1. Car
2. Alarm (front door + garage)
3. Thermostat
4. Quick actions
5. Lights
6. Favourites
7. Activity
8. Battery
9. ChargePoint

**Removed (owner decision 2026-11-27):** the small sizes of Alarm, Thermostat and Car, and the
small-only **Glance** summary widget. The Alarm readings screen, which only the small Alarm opened,
went with them. Values saved for them are ignored: a Glance card style is dropped when read, and an
old `hearth://alarm-readings/…` link opens nothing.

**Removed (owner decision 2026-11-28):** the **Doors** widget, which duplicated the Alarm card's
front door. The garage moved into the Alarm card as a second row under the front door: its state
and one button (Open when closed, Close when open, Stop while moving, none when unavailable or
last known). The button runs the same guarded door command the Doors card used
(`DoorActionIntent` → `DoorActionRuntime` → `HaStateStore.beginDoorOperation` / `executeDoorAction`),
one tap with no confirmation, as before, and now only for the garage selected at that moment
(`garageCommandTarget`). Settings → Home Assistant → Devices has a single **Garage door** picker
(`HaConfig.garageId`); with nothing saved, the one `cover.*` in the old Doors selection is used
(`garageSelectedID`), and editing Doors saves that garage first (`settingDoorSelection`) so the
edit cannot add or remove the Alarm card's row. The **Doors** picker stays: Activity and the
Goodnight key still read `doorIds`, not the new garage setting. A Doors card style saved earlier
is dropped when read.

**Surfaces built:**
- **AddWidgetGallery** — Categorized widget picker with Added/Needs-HA/Needs-CP status chips
  - 3 categories: Activity, Comfort & safety, Energy
  - Status chips show availability for each widget based on HA/CP connection state
  - Tapping a widget opens its per-widget settings page
- **WidgetPage** — Per-widget settings page for each of the 10 widgets
  - Preview mat showing the widget's one size with the person's own live data (the same preview
    the Card style page draws); a labelled example only when there is no data of theirs to draw
  - **Uses** — Prerequisite connections (HA/CP) with setup CTAs
  - **Safety** — Entity/device pickers (alarm, lock, climate, resume temp, doors, sensors, lights, scripts, favourites)
  - **Shows** — Display-name editor (App-Group state, keyed by `HomeWidgetKind`)
  - **Every day** — Goodnight-key route rows (defer to Phase 5, currently route to `.settings`)
  - **Look** — Card style link
  - **Remove** — Remove-from-Home CTA
- **CardStylePage** — All-cards and per-widget card appearance, ported from Android's `CardStylePage.kt` (see `docs/CARD-STYLE-IOS.md`)
  - **Background:** Status / Colour (8 swatches) / Black
  - **Text size:** Smaller / Normal / Larger
  - **Small print:** on / off
  - **Platform divergence (owner decision 2026-11-27):** iOS leaves out Corners/Glass/Wallpaper because an iPhone widget cannot draw them; the page does not present controls that are no-ops on a real widget.

**Integration:**
- Gallery accessible via Home dashboard "Add a widget" card
- Widget pages route from gallery picks and Home widget-card taps
- Card style page routes from WidgetPage Look row and Home Look row
- Display-name edits persist to App Group shared defaults
- Entity pickers update `HaConfig` and persist via `HaConfigStore`

**DEBUG hooks:**
- `-addGallery` → present AddWidgetGallery
- `-widgetPage <kind>` → present WidgetPage for the specified `HomeWidgetKind` (e.g., `-widgetPage car`)
- `-cardStyle` → present CardStylePage

**Deferred to Phase 6:**
- Goodnight-key Every-day rows route to `.settings` placeholder until Phase 5 builds real destinations

**Parity vs Android mocks:**
- Gallery categories and status chips match Android design (mocks 04/11)
- WidgetPage preview mat follows Android mock 16, without its slot-size picker (iOS widgets have one size)
- CardStylePage matches Android top to bottom for the axes iOS can draw (Background/Text size/Small print); every widget kind reads the style
- **Platform divergence:** iOS intentionally omits Corners/Glass/Wallpaper (Android mock 18) — documented above

---

## Morning commute (Phase 5a)

**Status:** ✅ Shipped

**Feature ported:** Morning commute auto-join from Android `ChargePointCommute.kt`

**Components built:**
- `MorningCommutePage` — Enable/disable morning commute, sensor detection status, copy-paste YAML config
- `CommuteStore` — Persistent enable/disable state via UserDefaults
- `commuteDecide` — Pure decision function (NOT a TCA reducer; 9 tests, ported 1:1 from Android `ChargePointCommute.kt`) returning `.armAuto` / `.notifySignIn` / `.none` from the two sensor booleans plus live CP state (charging / already-armed / signed-out) and the per-day stamps
- `CommuteFetch` / `CommuteStore` — HA `/api/template` sensor read + App-Group persistence (`enabled`, `lastArmDay`, `lastNotifyDay`, `lastHeard`)

**States implemented:**
- Enabled: Shows the enable toggle plus the Detection status row and the two sensor-YAML copy cards
- Disabled: Shows only the enable toggle — the Detection and YAML sections are hidden until the feature is turned on
- Notification permission: Requests permission when enabling if not yet determined; shows an amber Settings-deep-link banner when denied
- Detection status reflects sensor-fetch FRESHNESS, not sensor values: `.found` (green) when the last successful sensor read is recent (< 5 min), `.lastHeard(time)` when stale, `.waiting` (neutral) when no read has happened yet

**Integration:**
- Reachable via Settings → ChargePoint → Morning commute
- Engine runs in ChargePoint widget's 15-min refresh cycle (Phase 4 `CpWidgetProvider.timeline`)
- Reads two Home Assistant booleans: `commute_charge_now` and `commute_signin_needed` via `/api/template`
- Google Routes, geofence, and ETA calculations live in the owner's Home Assistant configuration (app only reads sensor values)
- Once-per-day guarantee: Never arms/notifies more than once per calendar day; a failed arm does NOT burn the day (retries allowed within the morning window)
- Acts once per day per branch: `commute_charge_now` → auto-joins the waitlist (no notification); `commute_signin_needed` while signed-out/expired → sends an iOS local notification nudging ChargePoint sign-in

**DEBUG hook:** `-morningCommute` presents MorningCommutePage directly for screenshots

**Parity vs Android:**
- Engine logic is a 1:1 port from Android `ChargePointCommute.kt`
- 9 `commuteDecide` tests port all Android test cases (never arms twice, retries within window, respects calendar day boundary)
- Detection status row is honest — it reflects real sensor-fetch freshness (reads `CommuteStore.lastHeard`, written on each successful fetch), never a hardcoded "Found"
- Both sensor YAML configs ship as copy-paste cards in the settings page
- Minor: iOS uses local notifications instead of Android system notifications (platform API difference)

---

## Leave-by / Travel / Safety (Phase 5b)

**Status:** ✅ Shipped

**Three net-NEW iOS features** (no Android port — built from approved mocks only):

**1. Leave-by times**
- Sends notifications 20 minutes before calendar events with a location
- Reminder includes house checks: alarm, locks, thermostat
- Calendar permission required (explicit opt-in with denied/`.restricted` banner)
- Notifications permission required (shows Settings deep-link when denied)
- Runs on a once-scheduled-fires-without-app model (no Phase-6 BGTaskScheduler yet)

**2. Travel days**
- Detects trips from calendar events marked with the word "Trip"
- Sends vacation-mode offer notification the night before (8 PM)
- Notification is a suggestion only — no auto-action until user confirms in-app
- Calendar + notifications permission required (same banners as Leave-by)
- Runs on the same once-scheduled model as Leave-by

**3. Safety alerts**
- Monitors critical home-security actions (arm alarm, lock doors)
- When an arm/lock action returns `.unconfirmed` or `.rejected`, retries once automatically
- If still not confirmed after retry, posts immediate notification ("Front door won't lock" / "Home alarm won't arm")
- Safety monitoring is purely additive: existing UI error flow unchanged, retry happens in background
- Garage/cover monitoring deferred (no `HaConfig` field yet)
- thrown-verify never false-alarms (Task-4 semantics: `verify()` throwing means "unknown state", not "failure")

**No-auto-action guarantee (all three features):**
- Notifications suggest actions only — nothing arms/locks/sets-Eco until the user confirms in `HouseConfirmSheet`
- Owner-flagged confirm-UX ruling: notification → in-app confirm sheet (not auto-execute)

**Components built:**
- `LeaveByPage` — Enable/disable leave-by alerts, shows examples, calendar/notification permission banners
- `TravelDaysPage` — Enable/disable travel alerts, shows examples, calendar/notification permission banners
- `SafetyAlertsPage` — Enable/disable safety monitoring, explains retry behavior, notification permission banner
- `HouseConfirmSheet` — In-app confirmation sheet for house actions (sample data for DEBUG hook)
- `HouseFeaturesStore` — Persistent enable/disable state for all three features via UserDefaults
- `HouseScheduler` — Unified scheduler for leave-by and travel notifications (reads calendar, plans notifications, reschedules on foreground)
- `SafetyMonitor` — `ActionExecutor` protocol + `monitorWithRetry` function for retry-once-then-notify semantics
- Safety hook in `AlarmActionRuntime.perform` — launches background retry Task when safety enabled and action returns `.unconfirmed`/`.rejected`

**Integration:**
- Reachable from Home dashboard "Every day" section → three rows with enabled-state subtitles
- Safety monitoring hooks into `AlarmActionRuntime.perform` (the central alarm/lock action execution point)
- Widget intents and app UI both use the same path, so safety monitoring covers both
- Scheduler runs on app foreground (`.onAppear` + scene-phase active) — Phase 6 will add BGTaskScheduler for true background rescan

**States implemented:**
- Calendar permission: `.notDetermined` / `.authorized` / `.denied` / `.restricted` with banners and Settings deep-link
- Notifications permission: same states as calendar
- Enabled: Shows examples and retry behavior descriptions
- Disabled: Shows only the enable toggle

**DEBUG hooks:**
- `-leaveBy` presents LeaveByPage
- `-travelDays` presents TravelDaysPage
- `-safetyAlerts` presents SafetyAlertsPage
- `-houseConfirm` presents HouseConfirmSheet with sample actions

**Phase 6 deferral:**
- True background rescan (BGTaskScheduler) — currently reschedules only on foreground
- Garage/cover monitoring — no `HaConfig` field yet, deferred

**Parity vs Android:**
- N/A — these are net-new iOS builds from mocks only (no Android equivalent)

---

## Goodnight key (Phase 5c)

**Status:** ✅ Shipped

**Net-NEW iOS feature** (Android planned, not yet built):

**One-tap Goodnight sequence:**
- Runs a fixed sequence: Close garage → Lights off (except keep-on) → Lock → Arm Night
- Triggered via lock-screen **App Intent** (`RunGoodnightIntent`, `openAppWhenRun=false`), NOT CoreNFC
- Active only within the night window (default 9 PM–5 AM, overnight-wrap handled via `goodnightActive` utils)
- **No-abort semantics:** A garage or lights failure still proceeds to lock + arm (see G3 ruling)
- **Per-entity best-effort:** One flaky light/cover doesn't skip the rest (see G1 ruling)
- Arm-mode is **Night with Home fallback** when the panel lacks Night capability (see G2 ruling)
- Garage covers sourced from the **Doors selection** in Settings (`haConfig.doorIds` filtered to `cover.*`)
- **No auto-run:** Only explicit intent invocation + window gate (no scheduled triggers)

**Reachability:**
- Home dashboard "Every day" section → Goodnight key row
- Per-widget page → "Every day" group → Goodnight key row (all widgets)
- DEBUG hook: `-goodnight` launch arg

**Components built:**
- `GoodnightPage` — Enable/disable toggle, overnight window editor, sequence explanation, lights/garage config editors
- `RunGoodnightIntent` — Lock-screen App Intent for one-tap execution (runs in widget-extension process)
- `GoodnightRuntime` — Sequential execution engine with best-effort entity handling
- `goodnightActive` utilities — Overnight time-range wrap detection (10 PM–6 AM crossing midnight)

**Integration:**
- Reuses `AlarmActionRuntime` for lock + arm (benefits from existing confirmation/safety behavior)
- Garage close uses `HaClient.closeCover`
- Lights off uses `HaClient.turnOffLights` with keep-on exclusion list

**States implemented:**
- Enabled: Shows overnight window, sequence explanation, config editors
- Disabled: Shows only the enable toggle
- Inside/outside window: Intent performs gate check at runtime
- Per-entity failures: Logged but don't block subsequent steps

**DEBUG hooks:**
- `-goodnight` presents GoodnightPage

**Parity vs Android:**
- N/A — Android Goodnight is planned but not yet built (iOS-first feature)

---

## Fix log (newest first)
- A3 ✅ improved: `invalidatableContent` added to the freshness stamp in all 7 refreshable widgets (Car/Alarm/Thermostat/Battery/Lights/Favourites/Doors) → "updating" redaction on tap. Spinner itself is an iOS wall. Build + screenshot `invalidatable.png` confirm normal render intact.
- A2 ⚠️ resolved as platform wall (researched, 8 Apple/dev sources): the under-widget label is system-drawn and NOT removable by any WidgetKit API; user-side hide only. Documented.
- A1 ✅ FIXED + verified: beacon hero is now the Android ~37% rail (`beaconSplit`), not 50/50. Screenshot `split-fixed.png` confirms. 131 HearthKit tests green.
- NEXT: per-element beacon positions vs the Android 352×222 slot grid (fonts, y-anchors), then the remaining per-widget state/copy audit rows.
- A4: converted all 5 gated intents (Disarm/Unlock/Garage/Mode-Fan/Snooze/Join) to run in place; removed all `openAppWhenRun`. BUILD SUCCEEDED.
