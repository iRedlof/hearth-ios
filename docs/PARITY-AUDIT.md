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

| Widget | Layout | States | Interactions | Copy/strings | Overall |
|--------|--------|--------|--------------|--------------|---------|
| ChargePoint | 🔍 | 🔍 | ✅ (in place) | 🔍 | ⚠️ |
| Car | 🔍 | 🔍 | 🔍 | 🔍 | 🔍 |
| Alarm | 🔍 | 🔍 | ✅ (in place) | 🔍 | 🔍 |
| Thermostat | 🔍 | 🔍 | ✅ (cycle in place) | 🔍 | 🔍 |
| Battery | 🔍 | 🔍 | n/a (read-only) | 🔍 | 🔍 |
| Activity | 🔍 | 🔍 | n/a (read-only) | 🔍 | 🔍 |
| Lights | 🔍 | 🔍 | 🔍 | 🔍 | 🔍 |
| Quick | 🔍 | 🔍 | 🔍 | 🔍 | 🔍 |
| Favourites | 🔍 | 🔍 | 🔍 | 🔍 | 🔍 |
| Doors | 🔍 | 🔍 | ✅ (garage in place) | 🔍 | 🔍 |

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

## Fix log (newest first)
- A3 ✅ improved: `invalidatableContent` added to the freshness stamp in all 7 refreshable widgets (Car/Alarm/Thermostat/Battery/Lights/Favourites/Doors) → "updating" redaction on tap. Spinner itself is an iOS wall. Build + screenshot `invalidatable.png` confirm normal render intact.
- A2 ⚠️ resolved as platform wall (researched, 8 Apple/dev sources): the under-widget label is system-drawn and NOT removable by any WidgetKit API; user-side hide only. Documented.
- A1 ✅ FIXED + verified: beacon hero is now the Android ~37% rail (`beaconSplit`), not 50/50. Screenshot `split-fixed.png` confirms. 131 HearthKit tests green.
- NEXT: per-element beacon positions vs the Android 352×222 slot grid (fonts, y-anchors), then the remaining per-widget state/copy audit rows.
- A4: converted all 5 gated intents (Disarm/Unlock/Garage/Mode-Fan/Snooze/Join) to run in place; removed all `openAppWhenRun`. BUILD SUCCEEDED.
