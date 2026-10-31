# Controlled native Car WidgetKit proof

The DEBUG A/B widgets now exercise the production Car entry provider, immutable ticket binding, UUID URL delivery and native readings screen using private persisted test stores. Ordinary Raised widgets, their supported families and their controls remain unchanged. This is a bounded route verification tranche; it does not authorize an accessibility-summary rollout or a release.

## Source and build

The source is based on `d4d0df03c5a74011665ac0fbeaf7f4a8a4c804b7`. The recorded candidate is `private-widgetkit-car-route-probe-descriptor-v3`, with compile-time DEBUG marker `car-route-probe-2026-10-31-v1`.

- Private run selection is resolved before the live app runtime. A sticky isolation sentinel prevents missing or corrupt probe storage from falling back to production configuration.
- Both slots use the existing provider and entry factory. A publishes 79%, B publishes 44%, and explicit controlled Refresh returns 80%. Each published callback persists its own immutable ticket before exposing its UUID.
- A DEBUG-only locked HA reader rejects symlinks, nonregular files, oversized files and missing state. It never reseeds a run after arming. Production and Release store behavior is unchanged.
- Scene and screen receipts record the original entry/ticket/digest and fresh request identity. Controlled actions remain inside the private run.

Root package verification passed 612 tests with zero failures or diagnostics. Package sources and all 72 package-test inputs remained unchanged for the final candidate. Signed simulator Debug and Release builds succeeded with zero compiler warnings/errors, signatures verified, and the ten recorded DEBUG markers were absent from the Release binaries. Independent source and build reviews found no outstanding corrections.

The source manifest covers 163 app/extension inputs (including package sources and `Package.swift`), 72 package-test inputs and 10 owned source files. The manifests bind the actual app and extension executable artifacts, including Debug dylibs. Simulator signing does not establish physical-device provisioning.

## Actual native evidence

A fresh iPhone 18 Pro simulator running iOS 27.0 was created and booted for this tranche:

- Device: `14DA83FC-CDCB-48BC-A4FA-541C75684A2F`
- Native surface: 402×874 pt; screenshots 1206×2622 px
- Run: `EE63B26E-2D82-4711-B4E6-A57C109E8B7B`
- Generation: `6B00FC8F-C243-491C-82A2-9F99198E777D`

The widgets were added through Apple's native widget picker. Route checks used actual Home Screen widget taps; direct URL opening, direct intent execution and launch arguments were not substitutes for WidgetKit delivery. Cold A terminated app PID 25173 and its widget tap launched a new app PID 27144. Warm checks retained PID 27144.

| Case | Bounded observed result |
| --- | --- |
| Cold A | Original 79% with exact rendered entry, saved ticket and whole-ticket digest; new process and fresh request. |
| Warm A from Live | Same original 79% record, fresh request. |
| Warm A from Settings | Same original 79% record, fresh request. |
| Warm A from Preview | Same original 79% record, fresh request. |
| Warm B | Original 44% with B's own entry, saved ticket and digest. |
| A after B | A retains its original 79% record after B publication/opening. |
| Held A replaced by B | A's cooperative cancellation/closed-screen completion cannot replace B's original 44% record. |
| Successful A refresh before B | A accepts a new 80% ticket; a subsequent B tap still opens B's original 44% ticket and digest. |

No opening triggered an automatic refresh. Ticket identity and navigation request identity remain distinct.

The frozen evidence manifest binds 222 files, including 79 native PNGs and 47 private-run receipts. Independent native evidence review confirmed the eight bounded cases, all recorded file hashes, installed source/binary correspondence and exact scene/load identities, with no material inconsistency. A targeted fatal-log check found no matching events for the candidate process IDs in its 30-minute window; that limited query is not all-device crash/ANR acceptance.

## Failures and interpretation

The initial Debug compilation failed because Widget requires a literal default initializer. The corrected signed V2 build then failed in the actual widget picker: WidgetKit rejects formatted/interpolated `configurationDisplayName` text. Static `LocalizedStringKey` A/B titles fixed that descriptor failure. Both failures and their original logs remain preserved.

Two result-checker assumptions were corrected without changing app code: scene receipts use `requestID`; `refreshSettled` records accepted/new-ticket-ID/digest, with 80% verified from its saved synthetic cache and native header.

The held-A test proves cooperative cancellation. It emitted no successful 80% reply in that case. The separate successful 80% refresh finished before B opened. Neither test proves rejection of an uncooperative successful A response arriving after B.

## Progress gallery and integrity

[Native controlled proof gallery](http://localhost:8780/platform-parity/readability/car-widgetkit-v3/PROOF.html) contains 38 selected evidence files and 12 unaltered full native screenshots. Its inventory and SHA256 list bind the copied subset. Native capture evidence is distinct from gallery browser screenshots.

Root browser checks verified all 12 image dimensions, 40 working evidence links, eight result rows, no page overflow at desktop and 402×874 CSS phone-width viewports, and no console errors. Full-frame links expose the original capture bytes.

Local frozen evidence: `/tmp/hearth-ios-car-widget-probe/native-fresh-pro-widgetkit-v3/`.

Source manifest SHA256: `2cb0355899ddf22585fb158fb6891f841b523a493e0415583523d788699d14fb`.

Debug build manifest SHA256: `c8e76a0ba03c1433f8ad83d84ef64e9612f9defea1cfacd5c29095d4bea396de`.

## Open acceptance gates

Uncooperative delayed success after B; exact Settings/reconnect probe returns; native process-death lease recovery; complete unavailable/setup/auth/expiry/eviction/corruption/selector cases; all 32 fields/actions at uncapped AX5; actual VoiceOver; production controls and adaptive summary; live authentication and successful Tesla handoff; all-ten-widget native acceptance; Android performance; physical-device provisioning and release readiness.

The Android performance candidate remains failed. There is no version bump, release or platform-parity completion claim in this tranche.
