# Car Production Readings Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development or superpowers:executing-plans task by task. Steps use checkbox syntax. Execution continues under the user's existing full code/build/test ownership instruction.

**Goal:** Bind every real Car widget entry to its own persisted immutable reading, make that exact reading reachable on cold and warm app launch, and recover abandoned read ownership before enabling production navigation.

**Architecture:** Create the ticket once from the coherent `CarLiveEnvelope`, persist it before publishing the entry, and carry only its UUID through navigation. The app opens the retained record and independently validates present account/vehicle ownership before Refresh. Add a bounded lease to both Car discovery and exact-route reads under the existing HA sidecar lock.

**Tech Stack:** Swift 6, SwiftUI, WidgetKit, AppIntents, HearthKit XCTest, locked App Group storage; existing iOS 17 deployment floor.

**Spec:** `/Volumes/xHome/Github/hearth/docs/design/platform-parity/readability/ACCESSIBLE-UX-NEXT.md`.

**Source context:** `/Volumes/xHome/Github/hearth-ios`, supplied branch `codex/widget-platform-parity`, inspected 31 October 2026. This is a read-only source audit. No Git commands, build/test runs, simulator/device operations, user authentication, or live HA requests were performed. The documented 542-test and signed-build foundation results are previous evidence, not results of this audit.

**Project authority:** `project.yml` is the persistent XcodeGen source of configuration; `.gitignore` excludes `*.xcodeproj`, and `README.md` instructs regeneration with `xcodegen generate`. The generated `Hearth.xcodeproj/project.pbxproj` is useful for inspection, not an authoritative edit target. The current app has generated Info metadata configured in `targets.Hearth.settings.base` and no `info` block; the extension already uses an XcodeGen `info.path`/`info.properties` block.

## Global constraints

- Keep approved ordinary Raised Beacons and current production family membership.
- Do not remove any production larger-text readings or controls until the complete destination and its actual widget launch path pass acceptance.
- Do not cap or shrink accessibility text, rasterize text, or add empty vertical expansion.
- Preview/parity examples have no live origins, credentials, transport calls, ticket-store mutations, or executable live actions.
- Do not look up current configuration during a tap to invent the opening record; no newest-record fallback for unavailable tickets.
- Navigation itself performs no Car refresh, Tesla handoff, security command, sign-in, or account change.
- No release/version bump follows from entry binding. The broader destination, native, state, command, and performance gates remain open.

## Current source findings

| Path | Current behavior | Consequence |
|---|---|---|
| `HearthWidgets/HearthWidgetBundle.swift:267–308` | `CarEntry` has only date/snapshot. Both real snapshot and timeline calls use `CarLiveSnapshot.fetch()`. Only `getSnapshot` explicitly checks `context.isPreview`; timeline has a DEBUG parity shortcut. | The entry has no immutable origin or destination. A snapshot-level prefix/scope reconstruction would be unsafe. |
| `Shared/CarLiveSnapshot.swift:12–22` | `fetchEnvelope()` returns the coherent envelope. `fetch()` may use `presentationSnapshot(currentContext:)` after an obsolete request. | Production binding must use `fetchEnvelope()` and its own `envelope.snapshot`. The fallback is compatible with existing snapshot-only presentation, but cannot become a ticket-bound entry. |
| `Shared/CarReadingsIntent.swift:5–36` | UUID-only intent, `openAppWhenRun = true`, app/extension target membership, in-memory main-actor gate. A UUID request event is distinct from the ticket UUID. | The intended execution location is the app. Direct fixture `perform()` is no evidence of system dispatch or cold launch. |
| `Hearth/HearthApp.swift:136–207` | Initial gate observation supports requests arriving before view creation. The identified sheet guards its Close/setup completion callbacks against replacement. The sheet is outside Live-tab readiness. | These are useful foundations. Actual cold/warm timing, replacement, scene targeting, and competing setup requests are still unproved. |
| `Shared/CarBeaconView.swift:78,126–134` | Ordinary refresh uses `WidgetRefreshIntent`; setup/sign-in uses `HaSetupIntent`; Tesla uses `Link(tesla://)`. Noncontrol card taps default to opening Hearth. | Keep these existing controls. A route must not wrap the whole card in a button that intercepts them. |
| `Shared/ParityCatalog.swift:174–196` | DEBUG fixture content replaces the production closure and disables hit testing. | A `.widgetURL` placed *outside* this wrapper can remain attached while fixture content is shown. Put production route modifiers inside the production closure. Hit-testing suppression is not a substitute for removing executable navigation metadata. |
| `Shared/WidgetGalleryView.swift` | Sample card is hosted with native input/focus/accessibility suppression. | Do not begin issuing production tickets for samples. Prefer an explicit Car inert interaction mode so no live intent or link is constructed in the sample subtree. |
| `HearthKit/Sources/HearthKit/HaStateStore.swift:265–338` | Both Car readers persist `collectionReads["car"]`; exact reads additionally persist `carRouteReadPrefix`. There is no claim time or expiry. | A dead exact read blocks later exact Refresh indefinitely. A dead ordinary discovery does too. Ordinary refresh/discovery can supersede the claim, but a widget reload request is asynchronous and is not guaranteed lease recovery. |
| `Hearth/CarReadingsScreen.swift:44–108` | Lookup opens the saved ticket; explicit Refresh issues and saves a new ticket; Close cancels the screen task. | Keep the original ticket. Cancellation settles persisted ownership only when the suspended fetch returns; process death bypasses that path. |
| `Hearth/LiveDashboardView.swift:100–119` | Live-tab creation/refresh starts ordinary Car discovery, independently from the readings sheet. | Cold launch can overlap sheet Refresh with discovery. Ownership prevents target substitution, but can produce “in progress” or “superseded” feedback. Test this overlap explicitly. |

The ticket store already bounds aggregate count/bytes and individual bytes, rejects changed same-ID payloads, and fails closed on corruption. A maximum 48-hour lifetime is **not** a minimum 48-hour retention guarantee: normal 15-minute entries alone produce 192 records in 48 hours, exceeding the 128-record count. Snapshot calls, multiple widgets, and sheet refresh tickets can shorten retention further. Eviction must remain an honest “reading unavailable” opening.

## Recommended navigation choice

Use one registered `hearth://car-readings/<ticket UUID>` URL for the real widget's noncontrol card tap and, later, its explicit Readings link. Decode it in the receiving `ContentView` scene into the same `CarReadingsRequest`/sheet presentation sink used by the existing intent. This keeps immutable tickets and the native destination intact while using WidgetKit's documented navigation surface.

This is a justified update to the spec's preferred intent path: current [Apple WidgetKit interactivity guidance](https://developer.apple.com/documentation/widgetkit/adding-interactivity-to-widgets-and-live-activities) recommends `Link`/`widgetURL` when an interaction only opens the app. [Apple linking guidance](https://developer.apple.com/documentation/widgetkit/linking-to-specific-app-scenes-from-your-widget-or-live-activity) supports one widget URL plus separate links and delivers the URL to the receiving app scene. Keep the Tesla link and refresh/setup intents as separate controls.

The existing intent is not known to be broken. Apple's interactivity documentation states that `openAppWhenRun = true` causes app-process execution. If the implementer keeps an intent-based explicit Readings button, first prove its actual WidgetKit execution; do not add a shared pending-request mailbox merely because the gate is in memory. Also declare foreground mode on iOS 26+ and restrict execution to `.main` on iOS 27+ with availability annotations, retaining the iOS 17–25 compatibility behavior. Local SDK interfaces confirm `supportedModes` is available from 26 and `allowedExecutionTargets` from 27; do not use a similarly named invented property. See [runtime configuration](https://developer.apple.com/documentation/appintents/configuring-the-runtime-behavior-of-your-app-intents) and [allowedExecutionTargets](https://developer.apple.com/documentation/appintents/appintent/allowedexecutiontargets).

For URL delivery, present in the receiving scene directly. Broadcasting a URL through the global gate would make multiple `ContentView` observers compete to consume it. The retained gate remains useful for the existing intent and controlled in-app fixtures; both ingress paths call one main-actor presentation function.

## Coherent entry contract

Create `HearthKit/Sources/HearthKit/CarReadingsEntry.swift` with:

```swift
public enum CarReadingsDestination: Sendable, Equatable {
    case ticket(UUID)
    case storageUnavailable
    case inert
}

public struct CarReadingsEntryPayload: Sendable, Equatable {
    public let entryID: UUID
    public let date: Date
    public let snapshot: CarSnapshot
    public let destination: CarReadingsDestination
}

public func bindCarReadingsEntry(
    _ envelope: CarLiveEnvelope,
    entryID: UUID = UUID(),
    ticketID: UUID = UUID(),
    date: Date = .now,
    persist: (CarReadingsTicket) throws -> Void
) -> CarReadingsEntryPayload
```

The binding transaction is:

1. Fetch exactly one envelope through `CarLiveSnapshot.fetchEnvelope()`.
2. Capture one entry UUID, one ticket UUID, and one date after completion.
3. Create `CarReadingsTicket(envelope: envelope, entryID: entryID, id: ticketID, issuedAt: date)`.
4. Save it once using `CarReadingsStore.store`, with that same issuance clock.
5. Publish the entry with `snapshot == envelope.snapshot` and `.ticket(ticket.id)` only after save succeeds.

Do not reread HA to build this ticket, call `presentationSnapshot(currentContext:)`, reverse-parse formatted snapshot fields, or issue/save a ticket from a SwiftUI body, intent `perform()`, URL handler, or rendering callback. An account/vehicle change immediately after save is expected: the ticket preserves the old record and app validation disables operating actions.

Successful telemetry is unnecessary for a ticket. Setup, authentication failure, no car, unidentified/no reading, historical, obsolete, and storage-unavailable envelopes retain their exact status. Their ticket validation remains nonoperating where required. A successful save does not make a prefixless record Refresh-capable.

If ticket construction/storage fails, retain the coherent `envelope.snapshot`, publish `.storageUnavailable`, and never expose the unsaved UUID. Use `hearth://car-readings/unavailable` only as a stateless explanation destination, with no latest-car lookup and no operating actions. The native message should say the widget reading could not be saved and offer Refresh widget/Settings. It must not assert the account changed. Existing ordinary controls remain as currently designed. A later summary must retain a reachable explanatory action on this branch, rather than showing an enabled-looking dead link.

Expiry/eviction/corruption after successful publication remains possible and must be handled by lookup. A retry for the **same** entry reuses the same envelope, entry/ticket IDs, and issuance date; a new entry has new entry/ticket IDs. Do not extend expiry or globally reuse “the latest” ID.

## Review focus

1. Account/vehicle replacement during fetch, between save and display, or after opening cannot attach a replacement snapshot to the old ticket.
2. A persisted discovery claim and a persisted exact-route claim both recover after process death; neither expired owner's late reply can commit.
3. Failed ticket persistence, eviction, malformed URLs, and app-group unavailability open only an explanation.
4. Preview/parity selection cannot inherit a live ticket URL from a previous entry or execute a refresh/Tesla/setup action.
5. Cold/warm navigation, competing setup requests, Close/replacement, external return, and underlying dashboard discovery retain the opening record and correct sheet ownership.

## Task 1: Bound Car read leases — prerequisite

**Files**

- Modify `HearthKit/Sources/HearthKit/HaStateStore.swift`.
- Modify `HearthKit/Sources/HearthKit/CarReadingsOrigin.swift`.
- Test `HearthKit/Tests/HearthKitTests/CarExactRouteTests.swift`.
- Test `HearthKit/Tests/HearthKitTests/CarLiveEnvelopeTests.swift`.

**Interfaces**

- Add `now: Date = .now` to `beginCollectionRead(_:expectedScope:expectedRevision:now:)` and `beginCarRouteRead(expectedScope:expectedVehiclePrefix:now:)`.
- Persist a Car-only lease with matching read ID, `startedAt`, and fixed `expiresAt`, alongside the existing claim/prefix. Keep non-Car readers unchanged.
- Use a 60-second lease initially. This is a read-ownership budget, separate from command pending timeouts and ticket lifetime. HA requests currently use 10-second request timeouts; the lease also allows token renewal and scheduling delay.
- A lease is active only for a finite clock with `startedAt <= now < expiresAt`. Expiry, backward time before the start, or missing/semantically invalid legacy lease metadata revokes the claim. Reject a nonfinite caller clock before mutation/transport. A structurally unreadable HA record still fails closed as corruption.

Recovery must happen under the existing sidecar lock before an exact claim is refused, and lease liveness must also be checked at both ordinary/exact commit points. Atomically clear ID, prefix, and lease when abandoned; leave cached payload and actual observation dates untouched. The expired owner never regains authority if no new request has started. A new owner receives a fresh UUID.

Ordinary discovery retains its existing ability to supersede an active exact read. Generic merge/failure still cannot settle an exact owner with a copied read ID. Preserve the lease with the Car claim across unrelated picker edits and door discovery; clear it on account replacement and settlement. A recovery write failure returns nonoperating storage feedback and performs no transport.

An expired same-target reply must not say another refresh occurred without evidence. If the store still returns only a rejected optional result, use neutral feedback such as “This refresh is no longer active · Try again”; alternatively return a typed expiry reason. Retain the original record and do not present the expired reply as a new observation.

- [ ] Add failing tests: reopen a second store after an uncompleted discovery/exact claim; reject a second exact claim before 60 seconds; accept at expiry without an intervening widget discovery.
- [ ] Add failing tests: expired late success/failure rejected even before a replacement claim; late former owner rejected after replacement; duplicate settlement remains single use.
- [ ] Add failing tests: legacy ID without lease, backward clock, invalid clock, account/vehicle replacement, and lease preservation across unrelated picker/door changes.
- [ ] Run the new tests to observe the missing-recovery failures; inspect the persisted file through test fixtures, with no process/device manipulation.
- [ ] Implement lease issuance/recovery/commit checks and pass captured fetch-start clocks through both fetch functions. Existing direct claim tests with fixed observation dates must pass their same test clock to claim creation, rather than mixing a real claim-start date with a historical completion date.
- [ ] Run `swift test --package-path /Volumes/xHome/Github/hearth-ios/HearthKit --filter 'CarExactRouteTests|CarLiveEnvelopeTests'`, then the full package suite. Review this prerequisite independently before production binding.

## Task 2: Immutable entry factory and failure branches

**Files**

- Create `HearthKit/Sources/HearthKit/CarReadingsEntry.swift`.
- Create `HearthKit/Tests/HearthKitTests/CarReadingsEntryTests.swift`.
- Modify `Shared/CarLiveSnapshot.swift` only if an injectable entry-fetch adapter is needed; preserve `fetch()` for existing snapshot-only consumers.
- Modify `HearthWidgets/HearthWidgetBundle.swift` Car entry/provider.

**Interfaces**

- `CarEntry` owns a `CarReadingsEntryPayload`; its `date`, `snap`, and destination come from that immutable payload.
- Real `getSnapshot` and `getTimeline` use one factory path; placeholders, `context.isPreview` in both methods, and DEBUG parity selections produce `.inert` without invoking the live factory.
- Keep the 15-minute timeline policy and Medium-only Car family membership.

- [ ] Add failing factory tests asserting saved ticket entry ID, scope, prefix, raw current/history/error/observation values, and published snapshot all derive from the one supplied envelope.
- [ ] Test current/history/auth/setup/no-car/unidentified/obsolete/storage-unavailable envelopes; newer same-car cache and replacement account changes after binding cannot change the returned payload.
- [ ] Test injected nil-store/save/oversize/corruption failures: coherent snapshot retained, no UUID published, `.storageUnavailable`; an existing ticket is never borrowed.
- [ ] Test two entries have distinct IDs; duplicate factory delivery for one prepared ticket does not refresh its expiry; reopened store restores exactly what the entry opens.
- [ ] Implement the pure binding function and injectable provider adapter. Preview branches must execute zero transport/persist calls.
- [ ] Run `swift test --package-path /Volumes/xHome/Github/hearth-ios/HearthKit --filter CarReadingsEntryTests`, then relevant ticket/store tests and the full suite.

## Task 3: Scene navigation without changing ordinary controls

**Files**

- Create `HearthKit/Sources/HearthKit/CarReadingsURL.swift` and `HearthKit/Tests/HearthKitTests/CarReadingsURLTests.swift`.
- Modify `Shared/CarReadingsIntent.swift` request/gate ingress.
- Modify `Hearth/HearthApp.swift` receiving scene and common presentation sink.
- Modify `Hearth/CarReadingsScreen.swift` stateless persistence-failure request handling.
- Modify `project.yml` under `targets.Hearth` to generate `Hearth/Info.plist` with the `hearth` URL scheme for all configurations. Retain the existing generated-metadata settings; regenerate the ignored Xcode project instead of editing `project.pbxproj` directly.
- Modify the production Car content closure in `HearthWidgets/HearthWidgetBundle.swift`.

**Interfaces**

- `public func carReadingsURL(for destination: CarReadingsDestination) -> URL?`.
- `public func carReadingsDestination(from url: URL) -> CarReadingsDestination?`.
- `.ticket` encodes only the UUID; `.storageUnavailable` uses the reserved `unavailable` path; `.inert` has no URL.
- `CarReadingsRequest` carries the destination and keeps a fresh event ID. Intent UUID strings and scene URLs converge on `presentCarReadings(_ request: CarReadingsRequest)`.

Strict parsing accepts only the `hearth` scheme, `car-readings` host, and one UUID or the reserved explanation path. Reject userinfo, port, query, fragment, extra segments, encoded path tricks, and arbitrary identifiers. `hearth://auth-callback` is not a readings route: do not log/consume OAuth query material or replace `ASWebAuthenticationSession` behavior.

Minimal persistent configuration: insert the following `info` block under the existing app target in `project.yml`, alongside `sources`, `dependencies`, `entitlements`, and `settings`:

```yaml
targets:
  Hearth:
    info:
      path: Hearth/Info.plist
      properties:
        CFBundleShortVersionString: "$(MARKETING_VERSION)"
        CFBundleVersion: "$(CURRENT_PROJECT_VERSION)"
        CFBundleURLTypes:
          - CFBundleTypeRole: Editor
            CFBundleURLName: com.rohit.hearth
            CFBundleURLSchemes:
              - hearth
```

Keep `GENERATE_INFOPLIST_FILE: "YES"`, `INFOPLIST_KEY_UILaunchScreen_Generation`, `INFOPLIST_KEY_UIApplicationSceneManifest_Generation`, and the existing Face ID usage description unchanged in `targets.Hearth.settings.base`. Do not add a competing per-configuration `INFOPLIST_FILE` override or independently hand-maintain URL keys in the generated file. The explicit version substitutions retain the current build-setting sources for version/build metadata. [XcodeGen's project specification](https://github.com/yonaskolb/XcodeGen/blob/2.45.4/Docs/ProjectSpec.md#target) states that `info` writes the plist and sets `INFOPLIST_FILE` for every configuration unless a settings override exists; its [Plist section](https://github.com/yonaskolb/XcodeGen/blob/2.45.4/Docs/ProjectSpec.md#plist) states that the file is written on each generation. Installed XcodeGen is 2.45.4. This audit checked configuration/documentation semantics; it did not regenerate or build the app.

Attach exactly one widget URL within the production closure inside `ParityWidgetContent`, never outside the wrapper. Initially retain the full ordinary Car view unchanged; the noncontrol card tap gains the exact destination. Existing refresh, Tesla, Settings, and Sign in targets remain independent. Do not implement the accessibility summary in this task.

- [ ] Test URL round trips, invalid/unknown inputs, `.inert`, and the reserved explanation branch; assert emitted URLs contain no account, vehicle, raw reading, error, server, or credentials.
- [ ] Test invalid/missing/expired/corrupt ticket openings perform no automatic read and never select the current car.
- [ ] Keep identified sheet ownership checks and fresh request IDs; repeated taps on one UUID can reopen the same original record.
- [ ] Implement scene URL delivery and common presentation. Keep the intent compatibility path; if it is used by the widget, add availability-correct foreground/main execution declarations and system-dispatch proof.
- [ ] Run `xcodegen generate` from `/Volumes/xHome/Github/hearth-ios` after the `project.yml` edit. Inspect the generated app target's Debug/Release `INFOPLIST_FILE` and `GENERATE_INFOPLIST_FILE`, confirming the new source selection and retained metadata settings survive regeneration.
- [ ] Run URL/core tests and signed Debug/Release app/extension builds. Inspect each final `Hearth.app/Info.plist` with `plutil`: `CFBundleURLTypes` contains `hearth`, bundle identity and version/build metadata remain correct, and the launch-screen/scene/Face ID keys are retained. Check intent metadata, app/extension membership, and absence of DEBUG fixtures from Release. The built plist, not the generated source plist alone, is the registration acceptance artifact.

## Task 4: Preview isolation and controlled native launch proof

**Files**

- Modify `Shared/CarBeaconView.swift` with explicit `.live`/`.inert` interaction selection, defaulting to existing live behavior for the dashboard.
- Modify `Shared/BeaconFreshness.swift` so an inert Car subtree constructs no `WidgetRefreshIntent`.
- Modify Car sample call sites in `Shared/ParityCatalog.swift` and `Shared/WidgetGalleryView.swift`; keep native input suppression.
- Modify/create DEBUG-only route probe support in `Hearth/CarReadingsFixtureHost.swift` and `HearthWidgets/CarReadingsRouteProbeWidget.swift`; register only in the DEBUG bundle/project.
- Modify `Hearth/HearthApp.swift` fixture runtime selection only within `#if DEBUG`.

The route probe must use the same entry factory, widget adapter, URL/intent ingress, native sheet, and ownership reducer as production, with injected private HA/ticket stores, controlled transport, inert tabs, and inert widget reload. Store its fixture-mode selection and private directory identifier separately from production HA/CP configuration so actual widget-driven cold launch can select the controlled runtime without launch arguments. It must not create or use a production route origin. Prefer a separate clearly labeled DEBUG probe over making existing parity samples navigable.

- [ ] Test/inspect sample/placeholder/preview/parity paths for zero production fetch/persist calls and absent ticket URLs/live intents/links.
- [ ] Verify a live entry already in memory becomes nonnavigable when parity content is selected; switching out of parity requires a new live entry, not a fixture ticket.
- [ ] Future authorized native tests: tap actual WidgetKit content on controlled data with the app terminated, backgrounded, and foregrounded on Live/Settings/Preview. Capture entry UUID, opened ticket UUID, original reading, process/bundle identity, and build/source hashes.
- [ ] Exercise repeated taps, Close/reopen, opening B while A is refreshing, pending setup sheet replacement, setup cancellation/return, scene/external-app return, and delayed underlying discovery. The correct original ticket remains visible; old work cannot dismiss/reopen/replace B.
- [ ] Exercise both lease-abandonment paths with a controlled store and real app relaunch. Report this separately from pure reopened-store tests.
- [ ] Test unavailable persistence, eviction, expiry, corrupted ticket storage, missing app group, changed account, and changed verified prefix using controlled data. Never recover by opening latest readings.

If underlying Live-tab Car discovery repeatedly defeats explicit sheet Refresh, add a narrowly scoped `suspendCarFetch` input to `Hearth/LiveDashboardView.swift`, driven by the pending/presented Car route, and pause only dashboard Car polling while that route owns presentation. Preserve all other cards/actions. Do this only against a failing overlap case; ownership already prevents unsafe substitution, and a blanket refresh/network coordinator is unnecessary.

## Acceptance gates

| Gate | Required evidence | Honest boundary |
|---|---|---|
| Read ownership prerequisite | Deterministic two-store/process-reopen lease tests, late-owner rejection, legacy migration, clock and account/target replacement cases; full HearthKit suite. | Unit reopen tests model process death; they are not actual app termination evidence. |
| Coherent entry | Exact envelope→saved ticket→published snapshot/UUID assertions for every typed origin and persistence failure; no view/tap ticket issuance. | Successful persistence does not promise the ticket survives bounded eviction. |
| Native widget launch | Actual WidgetKit cold/warm/background launches of the same adapter with controlled data; exact UUID/record matching and real sheet replacement. | Direct `perform()`, URL parsing, app fixtures, or signing alone cannot establish this. |
| Preview isolation | No production transport/storage/action route in all sample/placeholder/parity branches; native sample taps remain inert. | Disabled hit testing alone does not prove absence of a widget URL outside the subtree. |
| Complete destination | All 32 fields and independent cohorts/full errors reachable at uncapped AX5; original-record disclosure; Refresh, Close, Settings/reconnect and external return; Premium image below primary state; VoiceOver focus/reading order. | Existing matrices have bounded coverage, including fragment-only mini rows. No new whole-row or VoiceOver pass is implied here. |
| Production rollout | Signed Debug/Release builds, independent review of exact source/build identity, ordinary controls/family regressions, and all above gates. | Entry binding is not permission to replace the production larger-text summary before this gate. |
| Wider release | Remaining Alarm/Thermostat/ChargePoint destinations, action ownership, all ten widgets' native/state gates, and performance gates. | The Android performance candidate remains failed; no release or platform parity completion claim. |

A Tesla-unavailable alert pass does not prove successful Tesla handoff or selected-vehicle identity in Tesla. A reconnect screen transition does not prove authentication or resolve the separate upstream persistence race. Test those outcomes only within future explicit, controlled/native authorization and record their scope accurately.

## Minimal delivery order

1. Implement/review/read-lease recovery.
2. Implement/review the pure entry factory and all failure states.
3. Implement scene navigation and preview isolation; keep the existing full ordinary widget.
4. Prove actual controlled WidgetKit launches, replacement/return, lease recovery, and destination completeness.
5. Only after those gates, connect the reviewed adaptive summary and Preview relocation disclosure in a separate change.

The initial source audit was read-only. Execution and verification for this plan are tracked separately in its SDD ledger; the earlier foundation evidence remains frozen at its own source/build identity.
