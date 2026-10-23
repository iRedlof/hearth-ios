# Hearth iOS — port plan & status

## Approach

Mirror the Android app's proven split:
- **HearthKit** (Swift package) = pure logic, ported 1:1 from the Kotlin pure functions (parsing, view-model,
  helpers, HA client). Unit-tested on macOS with `swift test` — same discipline as the Android unit tests.
- **SwiftUI + WidgetKit** = the views, ported faithfully from the final Android layouts (the Car widget is at
  v1.4.28, including the readability/contrast fixes: bright right-panel text, Sentry-on red, unclipped location).

The Android widget is the spec — the design is already shipped & approved, so no new mockups; `docs/PORT-SPEC.md`
captures the exact logic to match.

## Device targets (Simulator)

iPhone 14 Pro Max (reference), 16 Pro Max, 17 Pro Max, and the smaller 17 Pro — the layout is size-responsive
(GeometryReader / relative sizing) so future 18-series sizes work too. WidgetKit family: `systemMedium` (the
Android car is a wide 2:1 card).

## Status

- [x] Repo + XcodeGen project (app + widget extension) + HearthKit package; builds the project graph.
- [x] Beacon palette + `CarSnapshot` (view data contract) + `CarBeaconView` (faithful v1.4.28 SwiftUI).
- [x] iOS 27 Simulator runtime installed; 14 Pro Max sim booted.
- [x] HearthKit logic port (Car model, carFromTemplate, carView, helpers, HaClient) + **24 unit tests green** (`swift test`).
- [x] Car widget **verified in the Simulator across all four sizes** (gallery screenshot), faithful to v1.4.28 (bright text, Sentry-on red, full location, real Tesla image).
- [ ] Wire the widget TimelineProvider → `HaClient` (POST /api/template) via App-Group config.
- [ ] App onboarding: HA sign-in (OAuth) / long-lived token, stored in the App Group.

## Roadmap (after the Car slice)

1. **Alarm** widget — ✅ **DONE & verified** (v1.4.26 design: blue "Disarmed" rail + shield glyph + "Disarmed at 7:00 AM", Front Door lock row, arm/disarm buttons; 15 tests). Picker in the gallery toggles Car/Alarm.
2. **Thermostat** — heat/cool setpoints + sensors.
3. **ChargePoint** — the waitlist/charging card (the big one; its session logic is intricate).
4. Shared: the Beacon design system (tones, surfaces, card styles) as reusable SwiftUI.
5. Config sync (App Group), background refresh cadence (15 min, matching Android), AppIntent "Check again".

## Notes / gotchas carried from Android

- Home Assistant: the Car widget makes a single `POST /api/template` call with an auto-discovery Jinja template
  (no stored car entity). Auth = long-lived token or OAuth refresh (renew 60s before expiry).
- "Unknown" discipline: HA `unknown/unavailable/none/""` → nullable, never a default. Load-bearing for tone.
- Signing: not set up here (0 identities); Simulator needs none. Physical device needs the user's Apple ID.
