# Wiring the widgets to live Home Assistant data

The widget **views** and the **`HaClient`** (POST `/api/template`, Bearer auth, OAuth refresh — all
ported + unit-tested in HearthKit) are done. The remaining step makes the widgets show *your* data
instead of the sample. It needs your HA URL + token, so it's split out here.

## 1. Shared config via an App Group

The app writes the HA config; the widget extension reads it. On iOS that's an **App Group**:

- Add capability `com.apple.security.application-groups` → `group.com.rohit.hearth` to **both** the
  `Hearth` and `HearthWidgets` targets (in `project.yml` under each target's `entitlements`, then
  `xcodegen generate`).
- `Shared/HaConfigStore.swift`: encode/decode `HaConfig` (HearthKit, already `Codable`-able) to
  `UserDefaults(suiteName: "group.com.rohit.hearth")`. The token is sensitive — for a real build move
  it to the Keychain with `kSecAttrAccessGroup`; UserDefaults is fine for the first Simulator pass.
- **Signing note:** App Groups work in the Simulator without a paid account, but a *device* build needs
  your Apple ID / team selected in Xcode (the group id must be registered to the team).

## 2. App onboarding

A simple SwiftUI form in `Hearth/`:
- HA base URL (e.g. `https://home.example.com`) + a **long-lived access token** (HA → Profile →
  Security → Long-lived access tokens). This is the quickest path and matches `HaConfig.token`.
- (Later) full OAuth sign-in: `HaClient`/`HaAuth` already implement the `/auth/token` refresh flow;
  add the `/auth/authorize` browser round-trip with an `ASWebAuthenticationSession` and the
  `hearth://auth-callback` redirect.
- On Save: write `HaConfig` to the App Group, then `WidgetCenter.shared.reloadAllTimelines()`.

## 3. Widget TimelineProvider fetch

In each provider's `getTimeline`, replace the `.sample` with:
```swift
guard let cfg = HaConfigStore.load(), cfg.hasAuth else { /* "needs setup" snapshot */ }
let json = try await HaClient(cfg).template(CAR_TEMPLATE)      // or the alarm/climate query
let car = carFromTemplate(json)
let snap = carSnapshot(car, now: .now, stale: false, checkedAt: .now, zone: .current, locale: .current)
```
Cadence: `.after(now + 15*60)` (matches the Android 15-min WorkManager). Add an `AppIntent`
"Check again" button to force a reload.

## 4. "Needs setup" state

When no config: render the card with a muted tone + "Open Hearth to sign in" so the widget is never
blank. (The Android equivalent is `beaconNeedsSettings`.)

## Status

Not yet implemented — deferred because live data needs your HA URL + token. Everything it depends on
(`HaClient`, `HaConfig`, `carFromTemplate`, the snapshots) is ported and green.
