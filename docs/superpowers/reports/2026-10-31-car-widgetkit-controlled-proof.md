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

## Settings S1/S2 supplement

The separate frozen Settings tranche is at `/tmp/hearth-ios-car-widget-probe/native-fresh-pro-settings-v1/`. It used source commit `8d0a9cceb9b5d8176e691520041fd4911553bb09` and the same installed signed v3 app/extension binaries. Source inventories and all eight runtime artifact hashes remain unchanged; this tranche required no rebuild.

The existing widgets published newer timeline entries before these checks. Their exact identities differ from the earlier v3 cases:

| Slot | Entry UUID | Ticket UUID | Whole-ticket digest | Battery |
| --- | --- | --- | --- | --- |
| A | `07A1272E-9ED1-452F-8C99-9C5975DB2FAF` | `8F0C2E68-5A7C-4227-8D46-CC4B931B910B` | `a99cc5abc7d261030dd5e0b918db4fd8f720ed1e41019ec0296c82a186d62353` | 79% |
| B | `51A0316B-25D0-4873-877F-7932F2E37594` | `A1360006-A4B2-4C92-974F-EC51FC72939C` | `d49669670ddb4a690d4c29c94aa7085e9d1e86e4334488d01dc16dcc13009378` | 44% |

**S1 — bounded pass.** An actual Home Screen A widget tap opened request `74029209-EE35-4967-BF7D-0B3BB3449DD5`. Native “Home Assistant settings” and “Back to car readings” actions returned the same entry, ticket, digest and original 79% reading under fresh request `FCFD6A19-4437-4F59-BA98-F07B95483CB2`. This was an internal return following WidgetKit ingress.

**S2 — bounded pass.** A second A opening left its return pending in Settings. An actual B widget tap then opened B's exact 44% record under request `99F1791C-E6CB-4D5F-98F4-415D2A16D391`. Closing B and subsequently tapping the native Home Screen app icon left Settings without A's old return action or a restored readings sheet. No S2 `settingsReturned` event occurred. This demonstrates observed return-context invalidation; no inaccessible stale callback was injected.

Independent audit verified all **83** manifest files, **24** native PNG/AX provenance pairs, and **17** receipt deltas. The **21** copied receipts include those deltas plus four provider/render records for the newer entries. Canonical saved-ticket digests match the loaded records. Neither opening nor the internal return triggered a refresh.

Both cases used ordinary native text size and an inert controlled Settings tab on the same simulator/run. They establish no live Settings mutation, account/prefix revalidation, reconnect, AX5, VoiceOver, or delayed-success coverage. The remaining acceptance gates below stay open.

## Controlled reconnect R1–R4 supplement

The frozen reconnect evidence is `/tmp/hearth-ios-car-widget-probe/native-fresh-pro-authentication-v2/`, run `47EDFFB0-9604-404D-9209-CD37788610FA`. Runtime source and installed v3 binaries remain unchanged from commit `8d0a9cceb9b5d8176e691520041fd4911553bb09`; no new source implementation or build was needed. The controlled `authentication` scenario produces saved 401 authentication-failure explanations, with no successful telemetry or identified vehicle prefix.

| Slot | Entry UUID | Ticket UUID | Whole-ticket digest |
| --- | --- | --- | --- |
| A | `0EB71B1E-0869-4CC3-8AEA-33B0C3B3770A` | `9E77788E-F2B9-45B3-9ADB-FE913B9BB663` | `bbb919abf1eb5b1bf11b0f19fd0f9dd68e39784dd0192fc234ed2f1535a570ae` |
| B | `11ABA66A-CF1F-4D81-B3C5-0C0712BFE446` | `CC15F5B5-D49A-457A-90A5-6564D3F249C8` | `620f7929ac933f96988b406172b661d51a001189b82c6618014db6fb51962537` |

Independent audit accepted four bounded native cases:

- **R1 — Cancel:** actual A widget ingress, then explicit reconnect Cancel, returns A's exact saved failure record with fresh internal request `0AA0AEF6-83A3-4E95-98CC-0D34E7BB50AD`.
- **R2 — controlled Complete:** “Complete controlled return” creates fresh request `0731792B-FD76-4FF9-8178-555C4EA4250D`, retaining the same A failure identity and explanation. Successful authentication remains untested.
- **R3 — gesture retention:** a downward navigation-bar gesture leaves reconnect visible with Cancel and Complete available. The fallback retains the screen; no swipe dismissal or swipe return is claimed.
- **R4 — B replacement:** an actual B widget tap replaces A's third pending reconnect with B's exact saved record. Close and subsequent native app-icon reactivation leave the controlled Live host visible, with no observed A restoration or third-transition return/cancel event. No inaccessible stale callback was injected.

The audit verified **78** manifest files, **21** native PNG/AX pairs, **16** receipt deltas and **20** copied receipts. `CORRECTION.json` preserves the v1 baseline-count error: v1 incorrectly called all 21 joined records deltas; v2 subtracts the five baseline records. The 20 receipt copies contain 16 deltas plus four provider/render records, excluding the baseline armed record. All capture bytes and the command log are unchanged from v1; joined route results are unchanged apart from candidate labels. This is a corrected evidence copy, not another native execution.

The [reconnect gallery](/Volumes/xHome/Github/hearth/docs/design/platform-parity/readability/car-widgetkit-reconnect/RECONNECT.html) contains 30 files, including 26 verified evidence copies and 10 full native PNGs. Browser QA is separate from that integrity audit.

These ordinary-size controlled cases triggered no opening/return refresh. Real authentication, successful reconnect telemetry, account changes, unobserved stale callbacks, other reconnect branches, AX5 and VoiceOver remain open.

## Recovery F1–F3 supplement

Independent audits accepted three further bounded cases using actual A Home Screen widget ingress. All three reused the unchanged runtime source and signed v3 binaries associated with compiled-source commit `8d0a9cceb9b5d8176e691520041fd4911553bb09`; no new build was performed.

The frozen evidence folders are under `/tmp/hearth-ios-car-widget-probe/`. Each audit verified every manifest hash/byte count, native PNG/AX provenance pair, and receipt delta:

| Case / frozen folder | Manifest files | Native PNG/AX pairs | Receipt deltas | Copied receipts |
| --- | --- | --- | --- | --- |
| F1 · `native-fresh-pro-persistence-failure-v1` | 38 | 7 | 8 | 12 |
| F2 · `native-fresh-pro-expired-v1` | 38 | 7 | 8 | 12 |
| F3 · `native-fresh-pro-setup-v1` | 47 | 11 | 9 | 13 |

**F1 — persistence failure.** Visible A entry `D71124F6-E851-44FF-86D5-28BCE59F6CD6` has no saved ticket or digest. Its native tap opens the reserved unavailable route with `lookupOutcome=notRequested`, `routeStatus=storageUnavailable`, and `ticketID=none`. This is visible-widget provenance, not a saved-ticket join; `notRequested` is a typed outcome rather than a measured lookup counter. Controlled Settings Back creates fresh request `6BD8CE8F-09BA-42CA-A315-7168865282F1` with the same unavailable explanation.

**F2 — expired ticket.** A requests saved UUID `4C24162B-5407-45FD-8A3E-8A7D8A981E92`, prepared as expired before lookup using the existing controlled clock and normal 48-hour lifetime. Both initial load and fresh Settings return `FEECE4D6-3905-4943-B5B8-91EF17C2B986` report expiry for that UUID. The expired lookup supplies no usable opening entry/ticket/digest or telemetry fields; provider data is not substituted into the destination.

**F3 — valid setup record.** A's available setup ticket `D072A92D-3106-4B5A-AC6D-DC312B2F89B7` retains entry `E6A9283D-D2E8-4FB6-8C3C-61EF58DA24CD` and digest `3f33dc2dbc17cd5218ebe90fbc292594023c6e0ac19c508c2badb51ccefbddc8`. It has no telemetry or identified prefix. The provider records `transportCount=0`, which is a controlled transport counter. Connect Home Assistant opens inert Settings; Back creates fresh request `3694ACC7-9BA5-4AAF-AC5C-C68590182FC6` preserving the exact setup record and explanation.

Each case exposes “Refresh widget” and records `controlledResult=inertReload` with explicit DEBUG feedback. This verifies inert feedback, not actual widget reload or recovery. F3's complete feedback was verified after an additional native scroll. Close leaves the controlled Settings host without Back to car readings in all three cases. Each case has one external widget ingress and two screen loads, distinguishing internal return from a second widget tap.

These ordinary-size cases preserve their appropriate failure/setup state without telemetry substitution, operating vehicle actions, or live authentication. They do not establish later reactivation, process-death recovery, delayed-callback behavior, AX5, VoiceOver, or the untested failure branches below.

## Current A at maximum native text size

The frozen evidence is `/tmp/hearth-ios-car-widget-probe/native-fresh-pro-current-ax5-v1/`, run `1CB84D81-9066-408A-AB2E-59AC24874D08`, on the new iPhone 18 Pro / iOS 27 simulator. CoreSimulator reports requested and effective content-size category `accessibility-extra-extra-extra-large`. A native Home widget tap opens entry `682583D9-552F-4840-9F86-3013ABCD4386`, ticket `49C4616F-ABF0-46E2-AE63-DB3DA39C2CAF`, digest `d76225da981d23d8d9740cde3883b347693829a2080fc32ab02346c803cc1fa3`, with the original 79% reading and fresh scene request `3E0540CE-01DF-4A9C-8E4B-D4FE3E9D5940`. Changing text size caused a WidgetKit republish; the selected identity and pre-ingress baseline come from that new publication.

Independent bounded native audit passed **108** manifest files, **40** native PNG/AX pairs, **four** receipt deltas and **eight** copied receipts, alongside unchanged source inputs and installed v3 artifacts. An expert personally viewed all **36** destination captures. All **32** current fields, **nine** source-row instances, the long vehicle name, primary state, full explanatory notes and three action labels are readable in their selected captures, without intrinsic clipping or ellipsis. Thirty-five overlapping scroll captures establish reachability; they do not measure a minimum number of user swipes.

The complete source note is visible in capture007, with its AX frame ending at829.33pt. This exceeds the deliberately conservative820pt census boundary but fits the actual content window. Its separate visual finding does not widen the census predicate. `lastFrameSignature` retains capture033 rather than terminal capture034; the selected final Settings frame is correct, but that signature does not prove a repeated terminal scroll boundary.

Native Close center activation works. Refresh, Open Tesla and Home Assistant settings were reached and read, without activation. The controlled host's separate AX5 text overlap is excluded from destination acceptance. Actual VoiceOver, refreshed/original disclosure, other contexts, continuous hit regions and ordinary production widget typography remain open. The source-first layout also puts actions far down the large-text page; that is a hierarchy issue to address separately.

The targeted last30-minute fatal-log query for PID69596 returned no matching events; this is not all-device crash/ANR acceptance. No runtime source change, rebuild, version bump or release accompanies this check.

## Open acceptance gates

Uncooperative delayed success after B and unobserved stale callbacks; remaining Settings return cases including mutated account/prefix revalidation; remaining reconnect branches including real authentication/account changes and successful telemetry; native process-death lease recovery; untested corrupt, evicted, access-failed and selector branches, other unavailable outcomes, and actual refresh recovery; remaining AX5 action/refreshed-original/other-context acceptance; actual VoiceOver; production controls and adaptive summary; live authentication and successful Tesla handoff; all-ten-widget native acceptance; Android performance; physical-device provisioning and release readiness.

The Android performance candidate remains failed. There is no version bump, release or platform-parity completion claim in this tranche.
