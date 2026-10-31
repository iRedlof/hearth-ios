# Car readings route foundation

31 October 2026. This is a foundation for the accessible Beacon destination, not a production widget rollout or a release.

## What changed

`CarReadingsTicket` freezes the coherent Car envelope that a widget entry will open. It contains the exact account scope, verified Home Assistant vehicle prefix, raw current/history readings, their actual observation times and complete read failure. It has a random UUID and a fixed lifetime of at most 48 hours. It contains no connection configuration or credentials. Only its opaque UUID travels through `CarReadingsIntent`.

`CarReadingsTicketStore` persists bounded records in the App Group: 128 records, 4 MiB aggregate and 128 KiB per record by default. It uses a permanent sidecar lock and atomic replacement. A same-ID/same-payload retry cannot extend expiry; a changed payload under an existing ID is rejected. Unknown, expired, corrupt and evicted records never fall back to the latest vehicle. A successful save retains the incoming record even after a clock rollback.

`CarReadingsRouteSession` keeps the opening record distinct from a later explicit Refresh. The route revalidates account scope, configuration and current verified vehicle before a refresh and after its result. Close invalidates the screen's refresh claim. Late, superseded or cross-target replies cannot replace its displayed record.

`carTargetedTemplate(vehiclePrefix:)` requests all 32 existing Car state keys for the exact verified vehicle. It does not rediscover or substitute another vehicle. `HaStateStore` claims this read under its shared lock; ordinary and exact-route reads cannot settle each other's copied read IDs. A discovery or account replacement can supersede the read safely. The global discovery template remains unchanged.

`CarDetailedReadings` preserves all 32 states as structured rows, including separate doors, per-wheel pressure/warning, unknown Sentry and unavailable readings. Values use their own known unit attributes. It does not infer one wheel's unit from another. Whole-car fallback uses the same displayed cohort as the compact snapshot; retained and failed-read cohorts retain their own attribution and actual dates. An historical ETA never becomes a promise of current charging.

`CarReadingsScreen` uses a growing native Form with scalable text. It offers exact-target Refresh and explicit Open Tesla, complete errors and connection guidance. After Refresh, it retains the opening record in a disclosure. Every historical section repeats its cohort attribution. Missing/expired/changed routes explain why they cannot operate.

The app's Car, ChargePoint setup and HA reconnect destinations now use one identified sheet. Completion and dismissal callbacks check ownership before changing the current sheet or tab. This prevents an older sheet's completion from dismissing a newer Car destination; it does not change upstream authentication persistence ownership.

## Verification

The frozen source passed the full 542-test HearthKit suite with zero failures or warnings. This includes 94 new tests for exact-target refresh, numeric conversion bounds, full readings, ticket coherence, route lifetime and bounded persistence. Meaningful regression tests were observed failing before the corresponding fixes, including changed targets, copied read ownership, corrupted displayed dates, oversized numeric conversion, symlink handling and clock rollback.

Both signed Debug and Release simulator app/extension builds succeeded without warnings. The final V3 build manifest records 211 Swift/package/project sources, 12 additional asset/config files and all eight runtime Mach-O binaries, including the Debug executable dylibs. The root's V3 integrity review verified those 231 hashes and 20 Pro native artifacts without mismatches. All 136 HearthKit source/test files are unchanged from the 542-test run. V1 and V2 source/build identities remain separately frozen; their screenshots are not presented as captures of V3.

The DEBUG native host uses private controlled HA/ticket stores, inert background tabs and an injected widget-reload callback. The native screen and app gate are real. The controlled transport returns fixture data; the tests do not claim a live Home Assistant response.

Fresh owned iOS 27 simulators were created after the prior simulators were removed:

| Device | Logical display | Native pixels |
|---|---:|---:|
| iPhone 18 Pro | 402 × 874 pt | 1206 × 2622 |
| iPhone 13 mini | 375 × 812 pt | 1080 × 2340 |

The V1 bounded native matrix covers current, historical, authentication, expired, missing, changed-account and setup openings on both devices. Pro Close/reopen retains each of those seven original tickets; mini Close/reopen covers the complete original 79% record. Explicit Refresh changes the controlled battery reading from 79% to 80%, labels the new record and retains the original. A controlled 401 refresh displays historical readings and a full error. This matrix contains 60 Pro captures, 85 Pro scrolling supplements and 167 retained mini captures. Two superseded mini capture records remain as metadata and are excluded from artifact/pass claims.

The iOS toolbar reports a 76 × 36 pt visual Close frame. Sampled native taps 21 pt above/below its center and Pro corner samples successfully dismissed the sheet. These samples demonstrate hit-area extension beyond the reported visual frame; they do not prove every point in a 44 × 44 pt target or VoiceOver behavior.

Largest-text scrolling evidence is recorded separately from initial-screen fit. A first Pro crawl made only 20 of 32 combined field rows wholly visible between captures; it remains recorded as partial coverage. The slower 85-frame Pro supplement shows all 32 combined field rows wholly inside the readable viewport at least once. The mini audit records overlapping scrolling coverage for all 32 fields in each tested cohort, with 31/32 current rows, 26/32 displayed and 26/32 latest historical rows, and 28/32 authentication-history rows wholly contained at least once. A current ETA row is taller than the mini readable viewport and requires continuous fragments; it is not a whole-row-visible pass.

The unavailable-Tesla path exposed two successive presentation defects. V1 placed recovery feedback below the fold. Signed V2 added an immediate native alert that fit the Pro at AX1/AX5, but its repeated failure sentence pushed the ending behind OK on the mini at AX5. A native message swipe reached the ending; this remains a rejected initial-fit result. V3 keeps the failure in the title and shortens the alert to recovery guidance, while preserving the complete diagnostic in Result. Focused V3 native captures show the whole title, message and OK together at AX1/AX5 on both devices without an alert-content swipe. Actual OK dismisses the alert without refreshing or replacing the original 79% reading.

V3 retains nine Pro and 26 mini focused captures. The root separately verified all 78 mini PNG/AX artifacts and six installed Debug binaries against the final manifest without mismatches. A mini AX5 supplemental capture shows the original 79% and opening-record caption after OK without closing the sheet. An earlier supplemental reverse-swipe helper dismissed the sheet; its failed tool run remains in the command record and is not counted as successful retention evidence.

The native evidence uses real app screens, native HID taps/scrolls, original PNGs and accessibility geometry. It does not establish VoiceOver traversal, successful Tesla handoff, actual WidgetKit-to-app navigation or live Home Assistant behavior. No physical phone was used for this tranche. An earlier unsigned V2 build could not open the fixture's App Group storage; its setup failure is retained separately and is not a functional pass.

## Remaining work

- Bind the production `CarEntry` to a persisted immutable ticket at the coherent timeline boundary. The current production Car widget and its actions are not wired to this destination yet.
- Test real WidgetKit-to-app cold and warm intent execution. Direct fixture invocation of `CarReadingsIntent.perform()` proves only the in-app gate path.
- Finish native original-record disclosure, sheet replacement while work is pending, external-app/scene return, setup return and VoiceOver traversal. A Sign in again transition opens the real sign-in screen; no successful login or authentication persistence race is claimed.
- Finish the reviewed full-destination presentation, including the Premium car image below the primary state, before replacing any production summary or removing ordinary actions.
- Route-read claims currently have no automatic lease expiry. Explicit ordinary refresh/discovery can supersede a stranded claim; process-death recovery needs its own acceptance before production route wiring.
- Add complete origin-bound Alarm, Thermostat and ChargePoint destinations and command ownership before production accessibility summaries.
- Keep the broader native/state/performance release gates open. The Android performance candidate remains failed; this tranche does not bump a version or publish a release.

The implementation plan remains in `docs/superpowers/plans/2026-10-31-accessible-beacon-readings.md`. Local raw tests, manifests, independent reviews and native captures are retained under `/tmp/hearth-ios-car-route/`; published evidence must carry the same build hashes and scope.
