# Car readings route foundation

31 October 2026. This is a foundation for the accessible Beacon destination, not a production widget rollout or a release.

## What changed

`CarReadingsTicket` freezes the coherent Car envelope that a widget entry will open. It contains the exact account scope, verified Home Assistant vehicle prefix, raw current/history readings, their actual observation times and complete read failure. It has a random UUID and a fixed lifetime of at most 48 hours. It contains no connection configuration or credentials. Only its opaque UUID travels through the widget URL or compatible `CarReadingsIntent`.

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

- Production `CarEntry` binding and receiving-scene URL handling are implemented and source-reviewed. Prove actual WidgetKit-to-app cold and warm delivery before accepting the route or replacing larger-text controls. Direct fixture invocation of `CarReadingsIntent.perform()` and supplementary URL delivery prove only their app ingress paths.
- Finish native original-record disclosure, sheet replacement while work is pending, external-app/scene return, setup return and VoiceOver traversal. A Sign in again transition opens the real sign-in screen; no successful login or authentication persistence race is claimed.
- Finish the reviewed full-destination presentation, including the Premium car image below the primary state, before replacing any production summary or removing ordinary actions.
- Car reads now have bounded persisted lease recovery, verified with deterministic reopened-store tests. Actual app termination/relaunch recovery still needs native acceptance before the destination rollout.
- Add complete origin-bound Alarm, Thermostat and ChargePoint destinations and command ownership before production accessibility summaries.
- Keep the broader native/state/performance release gates open. The Android performance candidate remains failed; this tranche does not bump a version or publish a release.

The implementation plan remains in `docs/superpowers/plans/2026-10-31-accessible-beacon-readings.md`. Local raw tests, manifests, independent reviews and native captures are retained under `/tmp/hearth-ios-car-route/`; published evidence must carry the same build hashes and scope.

## Production entry prerequisites — 31 October 2026

The next implementation plan is `docs/superpowers/plans/2026-10-31-car-production-readings.md`.

Car discovery and exact-route reads now share a persisted 60-second lease. Exact Refresh recovers expired, backward-clock and legacy abandoned owners under the shared lock. Late success, failure and cancellation cannot commit, even without a replacement request. Revocation clears ownership metadata while preserving cached readings and their actual times. Nonfinite clocks fail before transport or storage mutation. Unrelated picker/door changes preserve the lease; account replacement clears it. Existing non-Car and command timeout behavior remains unchanged.

`bindCarReadingsEntry` saves one ticket from the supplied coherent envelope before publishing its UUID. Construction/storage failure keeps the envelope's displayed snapshot and yields a stateless storage-unavailable destination. It never adopts a newer account, cache or existing ticket. Placeholder construction can explicitly produce an inert payload.

The pure `hearth://car-readings/<UUID>` parser/encoder accepts only an opaque ticket or the reserved `unavailable` explanation, and emits no URL for inert entries. It rejects malformed authorities, credentials, ports, queries/fragments, escaped or extra path segments and unrelated authentication callbacks without consuming/logging them. The subsequent integration registers the scheme and wires the provider to the receiving scene.

The exact stable prerequisite source passed **580 HearthKit tests, zero failures and zero warning/error diagnostics**. Independent task reviews passed both specification and quality: 59 lease/store tests and 62 entry/URL/ticket/store tests. Thirty-one additional malformed URL inputs produced no unexpected acceptance. Meaningful RED evidence preceded implementation. Existing success/cancellation/ETA fixtures use explicit issuance clocks within the active lease; separate boundary tests verify exclusive expiry at 60 seconds.

These prerequisite results are core tests and source reviews, not new app/WidgetKit captures. Earlier V1/V2/V3 native images remain frozen at their own build hashes.

## Provider and scene integration — 31 October 2026

Both production Car provider callbacks now publish the coherent saved entry through one loader. The original dashboard snapshot path remains unchanged. Placeholder, preview, parity and gallery Car content is explicitly inert: it constructs no Car refresh/setup intent or Tesla link and issues no live ticket. A DEBUG generation token prevents an old live entry regaining its URL or controls after parity is activated and deactivated.

The real Car card carries its opaque URL inside the production content closure. The receiving scene decodes that URL locally and shares presentation with the compatible intent. Save failure opens a stateless explanation with Refresh widget, Settings and Close; it performs no record or current-car lookup and has no exact Refresh or Tesla action.

The full readings sheet places the primary state and Premium car image before bound source context, actual dates and controls. Settings exposes Back to car readings; controlled and ordinary reconnect Cancel/Complete return through a fresh screen event for the original destination. A Car-origin reconnect currently disables interactive dismissal and keeps visible Cancel. Ordinary reconnect remains dismissible. This bounded fallback was independently reviewed; it is not a gesture-return pass. An attempted generic dismissal callback failed ownership review and was removed before acceptance.

The stable integration's full HearthKit suite passed **591 tests with zero failures and zero compiler diagnostics**. Independent provider/scene specification and quality reviews passed. Signed Debug and Release simulator builds, including the explicit-return fallback, succeeded without compiler warnings. Both built app plists retain the `hearth` route, bundle/version, scene, launch-screen and Face ID metadata. Simulator App Group entitlements were checked separately from code-sign entitlements. Four DEBUG fixture selectors are absent from the Release executable.

New controlled app captures and native command records are retained under `/tmp/hearth-ios-car-integration/` with separate source/build manifests, including the Debug implementation dylibs. They are separate candidates from the earlier gallery images. Native checks, test-driver failures and their actual scope must be reported per candidate; this source/build result does not establish WidgetKit launch, VoiceOver, successful authentication or Tesla handoff.

A private persisted DEBUG actual WidgetKit probe, complete destination/return/accessibility acceptance, other widget routes and wider performance/release gates remain open. No version bump or release is claimed.
