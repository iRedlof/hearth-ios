# Car Medium readable summary implementation plan

> **For agentic workers:** Use superpowers:executing-plans to implement this plan task by task. Steps use checkbox syntax.

**Goal:** Make the production Car Medium primary reading and navigation readable at XXXL and accessibility text sizes, within its existing allocation.

**Architecture:** Add typed primary semantics to the existing raw detail selection, then bind them to the same immutable entry as its destination. One shared presentation chooses the existing Raised card or the reviewed larger-text summary; production, the controlled route probe and inert previews use that presentation.

**Tech stack:** Swift 6, HearthKit, SwiftUI, UIKit font metrics, WidgetKit.

**Spec:** `/tmp/hearth-car-readable-medium-next-ux-v1.md`, plus the user's bounded-height, readable-font and real-native-evidence requirements.

## Global constraints

- Car Medium only; no family, host-height, provider-command or full-sheet behavior changes.
- The ordinary CarBeaconView remains unchanged.
- Summary starts at Dynamic Type XXXL; no category cap or text scaling down.
- Primary derives from the exact captured raw cache/origin, not formatted snapshot labels.
- Current priority remains openings, unlocked, tire warning, low battery, charging, battery.
- Historical data says Last known; unknown data never asserts locked, shut or asleep.
- Whole card and Readings use the same immutable destination. Inert content has no link.
- Failed persistence visibly says Not saved and uses only the existing explanation route.
- Native captures, navigation checks and physical performance remain separate gates.

## Review focus

- Unknown battery/security states must not become a reassuring status.
- Cross-vehicle or unidentified replies must not supply a current battery answer.
- Authentication failure with retained telemetry must preserve Last known attribution.
- Publication invalidation must preserve the chosen presentation while stripping its route.
- Long names and persistence failure must fit without shrinking fonts or enabling a service action.

### Task 1: Typed semantics bound to the entry

**Files:** `HearthKit/Sources/HearthKit/CarDetailedReadings.swift`, `CarReadingsEntry.swift`, `CarReadingsEntryLoader.swift`; new `HearthKit/Tests/HearthKitTests/CarReadingsPrimaryTests.swift`.

**Interface:** `CarReadingsPrimary: Sendable, Equatable`; `CarDetailedReadingAttention.primary` and `CarReadingsEntryPayload.primary`.

- [ ] Write meaningful tests for raw priority, unknown/invalid battery, identity mismatch, recovery, retained history, exact persisted-envelope binding, failed persistence and inert loading.
- [ ] Run the tests against the unimplemented interface and preserve the red result; after adding the interface, preserve behavioral failures before implementing selection.
- [ ] Add typed cases to the existing detail selection without changing its displayed titles/messages or duplicating raw parsing. Bind the selected primary once from the envelope; snapshot-only initializers default conservatively to No reading, with explicit inert sample primary.
- [ ] Run the complete HearthKit suite. Expected: all cases pass with no failures.

### Task 2: Shared production presentation

**Files:** `Shared/CarBeaconView.swift`, `HearthWidgets/HearthWidgetBundle.swift`, `HearthWidgets/CarReadingsRouteProbeWidget.swift`, `Shared/WidgetGalleryView.swift`.

**Interface:** `CarWidgetPresentation(payload: CarReadingsEntryPayload, family: WidgetFamily)` consumes Task 1's typed primary and opaque destination.

- [ ] Preserve the ordinary card byte for byte; append a shared Medium presentation and summary view.
- [ ] Use the reviewed 12pt tone band, graphite gradient, concrete UIFontMetrics body/title3 primary and 15pt subheadline navigation, full wrapping and a minimum 44pt navigation target.
- [ ] At XXXL show identity only if its intrinsic height fits. At accessibility sizes keep identity in the navigation label and destination.
- [ ] Use short typed labels; with persistence failure show Not saved and an explanation target. Derive one URL for the card and explicit Link; inert content constructs neither.
- [ ] Route production and the controlled probe through the same presentation. Preserve primary when interaction invalidation strips the route.
- [ ] Update only the inert Car preview selection and disclose its larger-text handoff.
- [ ] Build app and extension. Expected: successful compiler output. Check normal-card bytes unchanged and all unrelated baseline paths preserved.

### Task 3: Review and native evidence

**Files:** Evidence under `/tmp/hearth-car-medium-readable-v1/`; the existing progress gallery only after reviewed captures exist.

- [ ] Obtain independent source/UX review and fix material findings with regression tests.
- [ ] Capture actual production-renderer examples at Large, XXXL, AX1 and AX5 with controlled coherent records; record real dimensions and effective category. Reject failed fits.
- [ ] With available authorized native UI control, verify actual Medium WidgetKit activation opens the exact saved ticket. If control remains unavailable, leave navigation and WidgetKit acceptance pending; fixture launches do not substitute for taps.
- [ ] Commit and push scoped reviewed source changes after the model suite and builds pass. Hold release until the full iteration's native, accessibility and performance gates pass.
