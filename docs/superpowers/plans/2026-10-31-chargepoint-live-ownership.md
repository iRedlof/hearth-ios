# ChargePoint live ownership implementation plan

> **For agentic workers:** Use superpowers:executing-plans task by task. This plan is already authorized for implementation; root owns independent review and product acceptance.

**Goal:** Move every live iOS ChargePoint reader, writer, widget action, and request onto the coherent ownership journal, preserving the approved Beacon experience.

**Architecture:** Extend the existing schema-2 foundation with strictly identified provider observations, bounded rendered origins, one durable operation, and conditional cookie revisions. An independent request lock serializes prepared URLSession tasks; the state transaction durably admits and synchronously starts them. One owned runtime and App Group adapter replace all split-key production paths.

**Tech Stack:** Swift 6, Foundation, flock, protected atomic rename, URLSession completion tasks, SwiftUI, WidgetKit/AppIntents, XCTest.

**Spec:** `/Users/rohit/.codex/worktrees/widget-platform-parity/hearth/docs/superpowers/specs/2026-10-31-chargepoint-ios-ownership.md`; current-source closure `/tmp/hearth-cp-ios-live-migration-current-v1.md`; final 47-case schema-2 foundation.

## Global constraints

- Preserve Raised/fixed compartments, readable typography, bounded sizes, one-tap actions, compact labelled Auto pill, held Open + Snooze-or-Leave, and chosen Auto/history across manual actions.
- Explicit desired Join/Resume/Pause; no execution-time toggle or target substitution. Current Pause and direct Link Open remain usable during reauthentication, pending, failed, or uncertain provider work.
- Local admission is atomic; account-wide provider mutations have no proven assignment compare-and-set. Admitted cancellation is uncertain, never replayed automatically.
- App Group unavailable/corrupt state fails closed; no `.standard` fallback, credential resurrection, formatted-snapshot identity, or retained split-key writer.
- Discovery and candidate sign-in have isolated captured authorities; originless legacy/gallery mutation controls are inert.
- Baseline `/tmp/hearth-cp-live-ios-v1/baseline-files.json` pins 500 files before edits. Existing unrelated docs/assets and `Hearth/Info.plist` must remain byte-identical.
- No Git, versions/releases, galleries, live providers, credentials, devices, or simulator operation. Coordinate package tests/native build with root; logs remain in `/tmp/hearth-cp-live-ios-v1`.

## Review focus

1. Identical labels with replaced membership/offer/session must reject old commands; unknown/malformed queue never grants Join.
2. Pause while manual work waits or completes must keep mode paused and retain monotonic history; automatic unsent work loses authority.
3. A late cookie/401/read completion cannot alter newer account/credential/observation ownership, including A→B→A.
4. Claimed/admitted crash recovery and timeout must consume the original action and require post-fence reconciliation rather than automatic replay.
5. Two app scenes, old MapKit results, and late WebKit/profile/renew callbacks must retain the original owner and cannot modify the current context.

---

### Task 1: Identified observations and durable action journal

**Files:** Create `HearthKit/Sources/HearthKit/CpObservation.swift`, `CpActionOwnership.swift`; extend `CpOwnership.swift`, `CpStateStore.swift`, `CpSnapshot.swift`. Tests: `CpOwnedObservationTests.swift`, `CpOwnedActionStoreTests.swift`, existing foundation/process tests.

**Interfaces:** `CpObservation` contains provider-only reading plus canonical phase/membership/assignment/session identity. `CpRenderedOrigin` is bounded Codable and contains only opaque context/queue/assignment/action/observation generations. `CpDesiredAutoAction` is join/resume/pause. `CpOperationOwner`, `CpOwnedOperation`, `CpFeedback` identify claim/stage/typed outcomes. Store exposes observation commit, command/explicit-Auto claim, preflight validation, operation outcome/reconciliation, and current envelope projection.

- [x] Add compiling failing cases for malformed/unknown versus known empty status, station order/duplicates, changed private assignment fields, wrong detail target, nil versus zero allowance.
- [x] Add failing journal cases for replay/concurrent claims, Pause/manual completion, explicit Join versus newly queued status, uncertainty/late completion/post-fence reconciliation, same-context fresh labels and history.
- [x] Coordinate/run focused RED; implement minimal behavior and run focused GREEN plus the unchanged foundation regression filter.
- [x] Preserve original observed timestamps, no-reading pending/Open, local Pause and imported invalid-selection pause. Validate persisted journal and never authorize from provider presentation strings.

### Task 2: Request authorities, serialized prepared-task admission, cookies

**Files:** Create the consolidated `HearthKit/Sources/HearthKit/CpOwnedHTTP.swift`; extend store/ownership. Tests: `CpOwnedHTTPTests.swift`, owned action tests, existing wire client and process tests. Existing naked client source remains a pure/legacy test dependency, with no live construction.

**Interfaces:** `CpRequestAuthority` distinguishes read/operation/discovery/sign-in. `CpRequestPurpose` determines the exact endpoint/body; the store validates purpose against authority. `requestCredential`, `authorizeAndStart(... synchronousStart:)`, and `commitResponse` retain account/candidate owner and exact credential revision. Prepared task exposes synchronous start/cancel and async terminal response; request lock is held through response/cookie handling.

- [x] Add failing cases for cookie rolls, revoked owner/Pause, preparation-time edits before start, durable-before-start evidence, and late metadata; prove independent gate contention and initially suspended URLSession cancellation. The foundation suite separately covers an actual oversized write guard. Protection/rename failure and process-exit transport fault injection remain unproven.
- [x] Add isolated discovery and candidate sign-in tests; active/candidate cookie chains never write each other. Verify exact existing endpoint/header/body behavior.
- [x] Coordinate/run RED, implement permanent cancellable request flock and completion-task bridge against root's official Apple research, then GREEN.
- [x] Never await while holding state lock. Before admission send nothing; after admission await terminal callback and preserve uncertainty. Only matching used credential revision can commit a cookie; 401 additionally requires live request ownership.

### Task 3: Owned runtime

**Files:** Create `CpOwnedRuntime.swift`; keep the legacy `ChargePointFetch.swift` pure helper unused by live callers. Tests: `CpOwnedRuntimeTests.swift`.

**Interfaces:** `refresh(runAuto:)`, `perform(origin:command:)`, `setAuto(origin:desired:)`, `search(owner:bounds:)`, and `signIn(owner:cookie:)` compose owned store and transport. Preflight uses captured operation target after every await; Auto uses existing pure decision helpers and never implicitly joins idle users.

- [x] Add failing runtime tests for target replacement during details/gate waits, shared app/extension duplicate Auto, manual mode preservation, unknown allowance, ack ownership, no implicit Join, and fresh-read reconciliation.
- [x] Coordinate/run RED, implement runtime and owned notification claims/history, then GREEN.
- [x] Provider errors, unsent cancellation, admitted uncertainty, and successful outcome remain distinct. Notification identity/preferences are claimed from coherent current state.

### Task 4: Complete product cutover

**Files:** Replace `Shared/CpSessionStore.swift`; update `CpLiveSnapshot.swift`, `CpWidgetOperation.swift`, all CP command/control/join/snooze intents, `WidgetRefreshIntent.swift`, `CpBeaconView.swift`, remove `CpJoinGate.swift`/`CpSnoozeGate.swift` and their explicit project references; existing CP provider and notification helpers consume the migrated adapter unchanged; CP portions of `Hearth/SettingsRuntime.swift`, `CpSettingsSection.swift`, `CpLocationSearchView.swift`, `CpSignInView.swift`, `CookieCaptureWebView.swift`, `HearthApp.swift`, `LiveDashboardView.swift`, `SettingsFixtureScreen.swift`. No unrelated widget redesign.

**Interfaces:** Adapter returns a throwing coherent context and owned runtime; bootstrap imports raw legacy values once then removes old keys only after a committed file/marker. `SettingsCpState` retains captured `CpSettingsOrigin`; settings edit receives that owner. Snapshot origin passes unchanged through widget entry/render/intent; missing origin rejects mutation. Search retains owner/query ID before MapKit; sign-in retains latest attempt through cookie/profile/renew.

- [x] Add failing adapter/runtime integration cases, and manually audit source closure for no old split writers/live naked client mutations. Migrate the Settings protocol and isolated fixture owner behavior together.
- [x] Wire real reads/actions/settings/search/sign-in/dashboard; remove dead naked legacy sheets or keep captured origins. Refresh reconciles, never clears a different operation. Open is independent Link navigation.
- [x] Audit all legacy keys and live `CpClient` constructions. Originless samples remain visual and inert.
- [x] Coordinate focused/full package suite and native app/extension compile; retain complete logs and exact changed-file pins.

### Task 5: Self-review and handoff

- [x] Check every current-source inventory row has a migrated caller and no alternate writer/dispatcher survives.
- [x] Compare untouched baseline bytes, including existing docs/assets/Info.plist; report exact source/test pins and all verification failures.
- [x] Freeze source for root's independent source/native/UX review after final rebuild and pins. Root owns physical/provider/performance testing and release/product acceptance.

The final deliverable is a wired production migration. Intermediate journal or transport GREEN is infrastructure evidence only and is not a repaired live widget claim.

## Verified implementation checkpoints and remaining acceptance

- Full Swift package: 751 methods, zero failures, `/tmp/hearth-cp-live-ios-v1/36-nested-ack-full-green.log`. Final app/extension generic Simulator SDK rebuild is `/tmp/hearth-cp-live-ios-v1/37-frozen-native-build.log`. No simulator or device was operated in this lane.
- Full production CP callsites now use one App Group repository/runtime; origins remain inert when absent. Captured account/selection/mode, current credential revision and exact provider target govern requests and publication. Existing legacy parser/auto/client helpers remain available for pure regression tests, not live mutations.
- Verified same-account reauthentication retains mode/history and rebases already admitted uncertainty, but retires claimed/preflighted unsent work; old prepared admission has zero starts.
- Positive idle accepts only exact string or nested-object `NOT_QUEUED`; malformed/missing/refusal evidence never grants Join. Positive PASS with empty provider membership retains Snoozed/timing display but cannot grant selected-building Rejoin/Leave/Resume. Additional provider membership schema needs read-only provider evidence.
- DEBUG in-process actual `AppIntent.perform` uses only a temporary UUID directory/suite and injected inert transport. A reserved fixture-origin prefix rejects before real repository lookup if the override disappears or the origin reaches production. Native host/capture, cross-process WidgetKit behavior, provider actions, timing/performance, and final product acceptance belong to root.
- One durable admission and one prepared URLSession task resume prove local authorization only. No provider compare-and-set or Darwin physical wire-at-most-once guarantee is claimed.

- Final reply review: explicit negative acknowledgement remains refused; missing/malformed/error-bearing nested replies and error-bearing Stop receipts remain admitted uncertainty. They require later owned reconciliation and cannot replay Auto.
