# ChargePoint on iOS — parity & the irreducible gap

ChargePoint is a **separate cloud** (not Home Assistant): a rolling `coulomb_sess` web-session cookie,
captured by its own login page in a `WKWebView`. The iOS port covers:

- **Auth**: `CookieCaptureWebView` captures `coulomb_sess`; `CpClient` sends it (Cookie + `cp-session-token`
  headers), reads the rolled cookie from every `Set-Cookie`, persists it. Profile call validates + names
  the account; `renewSession` mints the long-lived cookie.
- **Live state**: `fetchCpSnapshot` reads `userStatus` (+ `inlineStatus`, `chargingDetail`) → the waitlist /
  offer / held / charging hero.
- **Auto-waitlist decision**: `cpAutoDecide` (+ `CpRun` and all helpers) is ported **1:1** from Android and
  unit-tested with the same 22 scenarios. Auto-accept near the deadline, auto-snooze once, drive-now, done.
- **Auto runtime**: `cpAdvanceAuto` runs the decision on each refresh and performs accept/snooze via the client.
- **Commands**: join/leave/accept/snooze/unsnooze/start/stop (750ms×75 ack loop) in `CpClient`.

## What iOS cannot match (by platform, not by omission)

1. **Unattended background timing.** Android uses `WorkManager` periodic polling + **exact `AlarmManager`
   wakes** (`ChargePointDeadline`) to silently auto-accept/snooze at *deadline − 2 min* even with the app
   closed. iOS has no exact background wake and no guaranteed cadence: `cpAdvanceAuto` runs only when the
   widget/app refreshes (WidgetKit's ~15-min budget, a foreground open, or an opportunistic `BGAppRefreshTask`).
   → A tight offer can be missed with no foreground app. The **decision is exact; only when iOS lets it run
   differs.** Drive-now surfaces as a local notification (`CpNotify`).
2. **Instant offer detection.** Android's `NotificationListenerService` sees ChargePoint's own push in seconds.
   iOS has **no API** to read another app's notifications → offers are seen on the refresh cadence, not instantly.
3. **Boot re-arm.** Android re-arms exact alarms on reboot; iOS BGTasks don't survive reboot until next launch.

## Not yet ported (reduced display model)

- Plug-count / **joining from the widget** need a chosen location with map bounds (location search via
  `MKLocalSearch` is a follow-up); until then an idle signed-in user shows "Set up".
- The **rich per-state key row** (manual Accept/Snooze/Stop buttons on the card) — the reduced `CpSnapshot`
  exposes one action + the Auto pill; the auto engine covers automated accept/snooze, and "Open" hands off to
  the ChargePoint app for manual control.
- Floor levels, live charging stats rows, `Text(timerInterval:)` countdown.
