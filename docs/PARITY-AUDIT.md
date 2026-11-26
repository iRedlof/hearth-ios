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
| Doors | 🔍 | ✅ (garage in place) | 🔍 | not yet diffed |

**Cross-cutting copy gap:** Android freshness stamp reads **"Last check"**; iOS reads **"Checked"** (all beacon widgets).

## C. Settings parity
| Item | Status |
|------|--------|
| Entity rows show friendly names | ✅ parity |
| ChargePoint section (account/location/name/auto/alerts/sign-out) | ✅ parity |
| All pickers present (alarm/lock/confirm/climate/resume/sensors/lights/scripts/fav/doors) | 🔍 |

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

## Fix log (newest first)
- A3 ✅ improved: `invalidatableContent` added to the freshness stamp in all 7 refreshable widgets (Car/Alarm/Thermostat/Battery/Lights/Favourites/Doors) → "updating" redaction on tap. Spinner itself is an iOS wall. Build + screenshot `invalidatable.png` confirm normal render intact.
- A2 ⚠️ resolved as platform wall (researched, 8 Apple/dev sources): the under-widget label is system-drawn and NOT removable by any WidgetKit API; user-side hide only. Documented.
- A1 ✅ FIXED + verified: beacon hero is now the Android ~37% rail (`beaconSplit`), not 50/50. Screenshot `split-fixed.png` confirms. 131 HearthKit tests green.
- NEXT: per-element beacon positions vs the Android 352×222 slot grid (fonts, y-anchors), then the remaining per-widget state/copy audit rows.
- A4: converted all 5 gated intents (Disarm/Unlock/Garage/Mode-Fan/Snooze/Join) to run in place; removed all `openAppWhenRun`. BUILD SUCCEEDED.
