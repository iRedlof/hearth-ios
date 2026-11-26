# Hearth — iOS ↔ Android convergence decisions

**Bidirectional:** for each widget, pick the best design and make BOTH platforms match it.
This supersedes the one-way "Android is the spec" framing for the items below — some designs
now flow **iOS → Android**. Android app: `/Volumes/xHome/Github/hearth` (Kotlin/Glance).
iOS: this repo. Captured from Rohit's widget-by-widget review (voice); confirm before building.

## Cross-cutting (both platforms, every widget)
- **Freshness stamp wording:** standardize on **"Checked"** (concise) everywhere — consistent
  across iOS + Android. (Rohit: fine with either, but must be consistent; "Checked" chosen for
  the compact look. He can veto → "Last check".)
- **Reload button:** a **circular raised-surface button**, positioned to the **RIGHT of the
  "Checked …" stamp text**, on BOTH platforms.
  - iOS today: bare glyph, LEFT of the stamp → move to the right + add the circular surface.
  - Android today: already right-ish → ensure the circular surface + right-of-text placement.

## Thermostat — adopt the iOS design ON Android (port iOS → Android)
- Android adopts the iOS **compact layout / theme / overall size**.
- **+/− steppers right-aligned**; the "Heat to" label + temperature value **bigger** and aligned
  with the steppers.
- Adopt the **iOS thermostat icon** on Android (Rohit: "so good"). (Needs an Android vector
  equivalent of the iOS SF Symbol.)
- Port the iOS **functionality** too.

## Alarm — iOS compact base + these fixes, then port to Android
Keep the iOS compactness (Rohit: "compact and yet has everything"). On iOS, ADD the gaps:
- **Unlock button** (currently missing on iOS — "really need to add").
- **Icons** on Arm home / Arm away / Unlock (Android has shield/house icons).
- **Reload as a circular button** (like Android), positioned to the **RIGHT** of the "Checked …" stamp.
- Title shows **"Home"**, NOT "Home Alarm".
Then bring this converged design back to Android too.

## Car — (re-confirmed against current Android source, HEAD 9cf9a33)
- CURRENT Android: Lock/Doors are RIGHT-panel **raised fact chips** (`carFacts` slot); the LEFT hero
  carries Cabin/Outside/Tires sensor rows. ⚠️ Rohit recalled them as "left status" — reconcile when
  we review Car (keep right chips, or move to left as he described — his call).
- CURRENT Android car PHOTO is large (198×60 dp, full right-panel width) → iOS should enlarge.
**iOS changes (keep iOS compactness + fonts):**
- Put **"Unplugged" (left) and "Sentry on/off" (right-aligned) on ONE line** → frees the line Sentry took.
- Use the freed space to **enlarge the car photo to the max available** (toward Android's prominence).
- Reload = circular button on the right of the stamp (cross-cutting).

## ChargePoint — build Android's design ON iOS (port Android → iOS)
Rohit: "build everything that is there on Android onto iOS." Bring iOS up to the Android ChargePoint:
- Add the **ChargePoint icon/logo** (iOS missed it).
- Countdown **clock** leads the hero (Clock state); "go to level P#/charger" + **floor-level stats**
  (P2–P6 availability) in the right panel as state variants; per-state body variants.
- Reload = circular button on the right (cross-cutting).

## Preview gallery — port iOS → Android
Rohit loves the iOS Preview tab (each widget rendered at every size). Build the equivalent on Android:
a preview screen showing every widget at all supported sizes (use the existing debug
BeaconPreviewActivity as the base).

## Status — alarm/car/chargepoint goal (DONE)
- **Alarm** — iOS ✅ (`58feae5`: Unlock button, arm/unlock icons, circular reload right of stamp, "Home"
  title, compact) · Android ✅ (`2b757ac`: "Home" title; already had Unlock/icons/circular-reload;
  verified on the emulator via BeaconPreviewActivity).
- **Car** — iOS ✅ (`43c955d`: Unplugged+Sentry one line, enlarged photo, circular reload).
- **ChargePoint** — iOS ✅ (`aca57ce`+`ed6a6a9`: CP logo, countdown-clock hero, "Go to <charger>",
  per-floor stats). 133 HearthKit tests green.
- Cross-cutting reload (circular, right of a "Checked" stamp): iOS via shared `BeaconFreshness`;
  Android already matches (and already says "Checked", not "Last check").

## Still open (future passes)
- Thermostat → Android (iOS compact design + icon); Preview gallery → Android; Battery / Activity /
  Lights / Quick / Favourites / Doors convergence review.

---
## Accurate current-Android facts (source, HEAD 9cf9a33) — supersedes the stale screenshots
- **Reload button:** raised circular `BeaconSurface` (radius 15, 30×30 dp, 18dp icon / progress
  spinner), top-right, all 4 beacons. iOS = bare glyph → add circular surface + move right of stamp.
- **Alarm (current):** "Unlock" button IS present (inside the recessed Door well); Arm buttons DO
  carry shield icons when non-compact and ≤2 actions (text-only when 3-up/compact).
- **ChargePoint (current):** big countdown **clock** leads the LEFT hero (Chronometer, Clock state);
  "go to level" + "floor stats" are RIGHT-panel `details` **state variants** (not one fixed stack).
- **Surfaces:** current Android uses raised surfaces (chips/buttons) + recessed wells — a look that
  landed AFTER the in-repo screenshots (commit 76295b4).
- **⚠️ No accurate Android render images in-repo:** `docs/design/beacon-widgets/screenshots/` are
  pre-"Raised surfaces" and have ZERO ChargePoint. For a truthful side-by-side, need FRESH on-device
  screenshots of all 4 current Android widgets (352 + 403, light + dark), or regenerate via the debug
  BeaconPreviewActivity. The earlier `docs/parity-comparison/` Android images are therefore outdated.
