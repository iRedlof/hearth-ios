# Accessible Beacon Readings Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development or superpowers:executing-plans task by task.

**Goal:** Make larger-text Beacons readable within their existing native sizes, with complete readings and available controls reachable through an exact-target app destination.

**Architecture:** First preserve coherent fetch origins and raw readings. Prove the larger-text layout and scrolling destination with inert native fixtures before wiring production navigation. Add origin-bound routes and reuse existing command runtimes; only then replace the production larger-text dashboard.

**Tech Stack:** Swift 6, SwiftUI, WidgetKit, AppIntents, HearthKit XCTest, locked App Group storage.

**Spec:** `/Volumes/xHome/Github/hearth/docs/design/platform-parity/readability/ACCESSIBLE-UX-NEXT.md`

## Global Constraints

- Keep approved ordinary Raised Beacons and production family membership.
- No text-size cap, shrinking accessibility text, rasterized text, or empty vertical expansion.
- Preview fixtures have no credentials, transport calls or live mutation intents.
- A production summary cannot remove controls before its complete destination works.
- No release until all relevant native, state, command ownership and performance gates pass.

## Review Focus

- A changed HA account or discovered vehicle cannot inherit the previous card's readings route.
- Alarm panel and door freshness are independent; a door error cannot hide a fresh triggered panel.
- Thermostat auxiliary sensor failures cannot erase a fresh room reading.
- ChargePoint unknown/expired deadlines cannot produce an inverted countdown or enabled Snooze.
- A larger-text navigation button must remain fully visible and usable on the compact native host.

### Task 1: Coherent Car reading envelope

**Files:** `HearthKit/Sources/HearthKit/{CarFetch,CarReadingsOrigin,HaStateStore}.swift`, focused Car/store tests, `Shared/CarLiveSnapshot.swift`.

**Interfaces:** `carReplyIdentity(_:)`, `CarReadingOrigin`, `CarLiveEnvelope`, `fetchOwnedCarEnvelope(store:context:now:request:observedNow:)`, `CarLiveSnapshot.fetchEnvelope(now:)`.

- [x] Observe failing tests for whitespace/numeric identity, cross-vehicle history, replaced scope and overlapping replies.
- [x] Preserve request configuration and scope from one locked context.
- [x] Reconcile Car raw cache under the store's existing sidecar lock; retain actual observation times.
- [x] Return obsolete/unidentified/setup/auth/failure contexts explicitly rather than borrowing a current target.
- [x] Run focused tests, then the full HearthKit suite and independent review.

Completed in `b10ced24a763c76c2810d21a575a2e3a0d2aa7dc`. The 448-test HearthKit suite passed; Debug and Release simulator builds passed. Legacy cache without provable account ownership is deliberately not imported. Native cross-process route/refresh ownership remains part of Task 3.

### Task 2: Inert native layout proof

**Files:** new `Shared/AccessibleBeaconConcepts.swift`, `Shared/ParityCatalog.swift`, `Hearth/HearthApp.swift`.

**Interfaces:** DEBUG-only native summary catalog and an app-only inert scrolling fixture destination.

- [x] Build reviewed 12pt accent summary using semantic scalable text and a navigation target at least 44pt tall.
- [x] Demonstrate current, warning, historical, setup/auth and expired states without pretending mock actions are live.
- [x] Present full identity/context and existing state-specific controls in a growing, scrollable native app fixture.
- [x] Build Debug and Release; ensure the prototype is absent from Release.
- [x] Capture actual WidgetKit XXXL/AX1/AX5 at native family sizes and the real app fixture; reject clipping within the recorded prototype matrix.

The catalog contains 45 inert examples across the four Beacon kinds. The final v14 uses concrete `UIFontMetrics` primary and navigation fonts with the incoming category and a caption curve for identity. Earlier semantic-font renders did not demonstrate the required primary-font growth and were rejected. A later v13 Pro AX1 navigation render truncated “Readings”; v14 resolves the navigation font through the same explicit category path and preserves its semantic subheadline curve without shrinking. Panel authentication uses the panel's own error; a door-only authentication failure cannot hide a fresh triggered panel.

The frozen v14 matrix has 42 independently reviewed native WidgetKit captures covering 18 distinct examples across XXXL, AX1 and AX5 on the owned iPhone 18 Pro and iPhone 13 mini simulators. All 42 reviews recorded no visible overflow or collisions. Native Medium measurements are 349⅔ × 164⅓pt on the Pro and 333⅔ × 159pt on the mini. This bounded matrix is not all 45 catalog cases, all ten widgets, a VoiceOver pass, or working production navigation/actions. The evidence gallery retains two v11 panel-authentication comparisons and the v13 truncated-label comparison beside their v14 corrections; the original statuses and build identities remain intact.

Four directly launched Pro AX5 app fixtures completed scrolling and Close dismissal in 79 original captures from frozen v11. All 88 observed content labels had an accessibility frame entirely inside the readable viewport on at least one captured page. This is scrolling/geometry evidence, not proof of complete production data, VoiceOver order or live commands. The app fixtures and WidgetKit captures retain separate surface and build provenance.

### Task 3: Live navigation and complete readings

**Files:** proposed route/ticket model and store in HearthKit, `Shared/WidgetReadings{Intent,Gate}.swift`, `Hearth/WidgetReadingsSheet.swift`, fetch adapters and timeline entries.

- [ ] Test immutable ticket origin, expiry/unknown ticket, account/entity/vehicle/sensor/location replacement and cold/warm navigation.
- [ ] Store opaque tickets with no credential material; bind them at coherent entry boundaries.
- [ ] Build a full, uncapped scrolling destination from structured readings, preserving independent freshness and errors.
- [ ] Prove Car Refresh/Open Tesla and setup return on the exact route; then add Alarm/Thermostat/ChargePoint complete contexts.

Car foundation progress is documented in `docs/CAR-READINGS-ROUTE.md`. Immutable tickets, bounded locked storage, exact-target refresh, all 32 structured state rows, route-session lifetime and the native app destination are implemented. The frozen foundation passed 542 HearthKit tests and signed Debug/Release simulator builds. Controlled native app checks use newly created Pro and mini simulators. The V1 matrix covers seven opening states, exact refresh, failure and Close/reopen; a slower Pro scrolling supplement fully contains all 32 field rows. Mini coverage is recorded as overlapping fragments wherever a combined row cannot fit the viewport. V1's below-fold Tesla failure and V2's clipped mini AX5 alert remain rejected beside the focused V3 correction. V3 native AX1/AX5 captures show full recovery guidance above OK on both devices. The production `CarEntry` has not been bound to a ticket; direct fixture intent invocation is not a WidgetKit cold/warm launch pass. Original-record disclosure, route replacement/return, VoiceOver and the remaining presentation requirements retain separate acceptance bounds. The cross-widget Task 3 boxes remain open.

### Task 4: Controls and production summary

**Files:** existing Alarm/Climate runtimes; CP shared atomic claim/expected-origin command entry; shared Beacon adapters and preview disclosure.

- [ ] Test same-target revisions, duplicate dispatch, replacement offer/session/question and Stop Auto during pending work.
- [ ] Reuse existing HA dispatch/confirmation semantics; implement explicit desired CP Auto state and atomic cross-process ownership.
- [ ] Verify every ordinary action remains discoverable and honestly disabled where unavailable.
- [ ] Wire production adaptive summaries only after their live destinations and native fit are verified.
- [ ] Verify all ten widget families/states, performance and release gates against the original goal.

## Current iteration

Task 1 is committed and pushed. Task 2's bounded final native matrix and visual reviews are complete after the recorded font and state corrections. Task 2 is a design prototype, not a production accessibility pass. Task 3's Car route foundation is implemented with separately attributed native matrices and focused recovery corrections; production entry wiring, remaining route acceptance and the other destinations remain open. Tasks 3 and 4 remain required before production summary wiring or release. The Android performance gate remains failed; this tranche does not publish a release.
