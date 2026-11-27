# Hearth iOS — Routines Implementation Plan

> **CORRECTED CONSTANTS (Task 1 source-diff of Android `Routines.kt`, 2026-11-26):** threshold **4** occurrences (not 6), window **7 days** (not 14), cluster tolerance **±45 min** (not ±30), retention **28 days**, max **500** events (not 100). **Matching is ORDER-INDEPENDENT** — Android normalizes an action-set to a sorted-key signature, so `[lock.a, alarm.b]` == `[alarm.b, lock.a]`. This SUPERSEDES the stale "order matters" / 6 / 14 / ±30 / 100 values anywhere below (esp. Review Focus #1/#2/#5 and Task 4 UI copy). Implemented in `RoutinesSuggester` + tested.

## Goal

Port the Routines feature from Android to iOS, matching the approved v2 mocks. Routines is a **deterministic frequency suggester** that observes executed action-sets (alarm arms, locks, lights off, garage closes), counts repetitions, and **suggests** (never auto-runs) a one-tap routine when a pattern crosses a threshold (e.g., "Same as Goodnight key").

## Architecture

- **Pure logic in HearthKit:** `RoutinesSuggester` (record, count, shouldSuggest, matchesExistingKey) — Sendable, macOS-testable, no AppKit/UIKit.
- **ActionHistoryStore in Shared:** App-Group UserDefaults persistence mirroring `GoodnightStore` / `CommuteStore` pattern (injectable defaults, absent/corrupt→default).
- **Recording hooks in runtimes:** `AlarmActionRuntime`, `GoodnightRuntime`, `ClimateActionRuntime` call `ActionHistoryStore.record(...)` after confirmed actions.
- **RoutinesPage in Hearth/Settings:** SwiftUI page matching the mocks (toggle, learning state, learned cards, off-confirm dialog).
- **Navigation wiring:** Add `.routines` to `HomeRoute`, update `EveryDaySection` row, handle in `HearthApp.swift`.

## Tech Stack

- Swift 6, iOS 17+, SwiftUI, XcodeGen (`project.yml`)
- HearthKit SPM package for pure logic + tests
- App Group `group.com.rohit.hearth` for shared store
- Design system: `HearthGroup`, `HearthRow`, `HearthSwitch`, `HearthColor`, `HearthFont`, `HearthMetrics`

## Spec

**Design doc:** `/tmp/hearth-p5c/docs/superpowers/specs/2026-11-26-ios-android-parity-port-design.md` (Phase 5: feature ports → Routines)

**Mocks:** `/Volumes/xHome/Github/hearth-task-artifacts/hearth-settings/final-v2/19-routines.png`, `19b-routines-learning.png`, `19c-routines-off-confirm.png`, `19d-routines-undo.png`

**Behavior (extracted from mocks + Android v2 UX):**
- **Threshold:** 6 occurrences within a 14-day rolling window (inferred from "6 of the last 7" and "11 of the last 14" in mocks).
- **Action-set matching:** Exact entity-ID sequence match (order matters; e.g., `["lock.front", "alarm.panel"]` ≠ `["alarm.panel", "lock.front"]`).
- **Day-pattern detection:** Tracks day-of-week for each occurrence; labels as "Weeknights" (Mon–Fri), "Every day", or "M T W T F S S" pills.
- **Time clustering:** Groups occurrences within ±30 min of median time (e.g., 10:28 PM, 10:31 PM → "10:30 PM").
- **Mapping to keys:** If a suggested routine's action-set exactly matches `GoodnightStore.load().actionSet()` (computed from config), label it "Same as Goodnight key".
- **Never auto-run:** Routines only appear as suggestions on widgets/Home; user must tap to execute.
- **Local only:** "Stays on this phone. Turning off forgets everything."

## Global Constraints

1. **HearthKit purity:** All suggester logic (RoutinesSuggester, RoutineEntry, ActionHistoryRecord) lives in HearthKit, is `Sendable`, has no UIKit/AppKit, is macOS-testable.
2. **Date.FormatStyle:** Use `Date.FormatStyle` (thread-safe) for time formatting, never `DateFormatter`.
3. **Design tokens:** All UI uses `HearthColor`, `HearthFont`, `HearthMetrics` — no hardcoded values.
4. **Store pattern:** `ActionHistoryStore` mirrors `GoodnightStore`: App-Group suite, injectable defaults for tests, absent key → empty history (safe default).
5. **Never auto-run invariant:** No runtime path may execute a routine without explicit user tap. Suggestions are **read-only presentations**.
6. **XcodeGen + git-diff gate:** Add `ActionHistoryStore.swift` to `Shared` group in `project.yml`; `RoutinesSuggester.swift` + tests to `HearthKit/Sources/HearthKit/Routines/`; `RoutinesPage.swift` to `Hearth/Settings` group. Run `xcodegen generate` and verify `git diff --exit-code` passes (CI requirement).
7. **Verify APP-TARGET build:** `xcodebuild -project Hearth.xcodeproj -scheme Hearth build` must succeed after each task.

## Review Focus

Five inputs most likely to bite:

1. **Action-set matching correctness:** Entity-ID order must matter; `["lock.a", "alarm.b"]` ≠ `["alarm.b", "lock.a"]`. Test exact-match, partial-match (should NOT suggest), and empty-set edge cases.
2. **Threshold boundary:** Exactly 6 occurrences within 14 days should suggest; 5 should not. Test day-15 rolloff (old entry expires, count drops below threshold → suggestion disappears).
3. **Never-auto-run invariant:** Every code path that accesses a routine is read-only (display, label). No path calls a runtime with a routine's actions. Add assertion tests: `shouldSuggest` returns a *suggestion*, never executes.
4. **Deleted-key mapping:** If Goodnight is disabled or its action-set changes, a previously-matched routine may no longer map. Test: routine labeled "Same as Goodnight key" → user changes Goodnight config → routine must NOT crash, should show unlabeled or generic name.
5. **History size / pruning:** 14-day rolling window + max 100 entries (defensive cap). Test: 101st entry evicts oldest; entries older than 14 days are excluded from counts but retained (allow "revive" if pattern resumes).

## Tasks

### Task 1: HearthKit Models & Pure Suggester Logic

**Files to create:**
- `HearthKit/Sources/HearthKit/Routines/ActionHistoryRecord.swift`
- `HearthKit/Sources/HearthKit/Routines/RoutineEntry.swift`
- `HearthKit/Sources/HearthKit/Routines/RoutinesSuggester.swift`

**Files to modify:**
- `HearthKit/Sources/HearthKit/Goodnight/GoodnightConfig.swift` (add `actionSet()` method)

**Interfaces produced:**
```swift
// ActionHistoryRecord.swift
public struct ActionHistoryRecord: Codable, Sendable, Equatable, Identifiable {
    public let id: UUID
    public let timestamp: Date
    public let entityIDs: [String]  // Ordered action-set
    
    public init(id: UUID = UUID(), timestamp: Date, entityIDs: [String])
}

// RoutineEntry.swift
public struct RoutineEntry: Sendable, Equatable, Identifiable {
    public let id: String
    public let medianTime: Date
    public let entityIDs: [String]
    public let occurrences: [Date]  // All matching timestamps within window
    public let dayPattern: DayPattern
    public let matchesGoodnightKey: Bool
    
    public enum DayPattern: Sendable, Equatable {
        case weeknights  // Mon-Fri
        case everyDay
        case specific([Int])  // 0=Sun, 1=Mon, ..., 6=Sat
    }
}

// RoutinesSuggester.swift (pure functions, no state)
public enum RoutinesSuggester {
    public static func record(history: [ActionHistoryRecord], newEntry: ActionHistoryRecord) -> [ActionHistoryRecord]
    public static func suggestedRoutines(from history: [ActionHistoryRecord], now: Date, goodnightActionSet: [String]?) -> [RoutineEntry]
    public static func pruneHistory(_ history: [ActionHistoryRecord], now: Date) -> [ActionHistoryRecord]
}

// GoodnightConfig extension
extension GoodnightConfig {
    public func actionSet(allLights: [String] = []) -> [String] {
        // Returns the entity IDs in execution order: garages, lights (filtered by keepOn), lock, alarm
        // e.g., ["cover.garage_1", "light.kitchen", "light.den", "lock.front", "alarm_control_panel.panel"]
    }
}
```

**Interfaces consumed:**
- `GoodnightStore.load()` (existing)
- Foundation `Date`, `Calendar`, `TimeInterval`

**TDD steps:**

1. **Test: `testRecordAppendsNewEntry`**
   ```swift
   let history: [ActionHistoryRecord] = []
   let entry = ActionHistoryRecord(timestamp: Date(), entityIDs: ["lock.a"])
   let updated = RoutinesSuggester.record(history: history, newEntry: entry)
   #expect(updated.count == 1)
   #expect(updated.first?.entityIDs == ["lock.a"])
   ```

2. **Test: `testSuggestedRoutinesThresholdSix`**
   ```swift
   // 6 identical action-sets within 14 days → 1 suggestion
   let now = Date()
   var history: [ActionHistoryRecord] = []
   for i in 0..<6 {
       let timestamp = now.addingTimeInterval(TimeInterval(-i * 86400))  // Days 0, -1, -2, ..., -5
       history.append(ActionHistoryRecord(timestamp: timestamp, entityIDs: ["lock.a", "alarm.b"]))
   }
   let suggestions = RoutinesSuggester.suggestedRoutines(from: history, now: now, goodnightActionSet: nil)
   #expect(suggestions.count == 1)
   #expect(suggestions.first?.entityIDs == ["lock.a", "alarm.b"])
   #expect(suggestions.first?.occurrences.count == 6)
   ```

3. **Test: `testSuggestedRoutinesBelowThreshold`**
   ```swift
   // 5 identical action-sets → 0 suggestions
   let now = Date()
   var history: [ActionHistoryRecord] = []
   for i in 0..<5 {
       let timestamp = now.addingTimeInterval(TimeInterval(-i * 86400))
       history.append(ActionHistoryRecord(timestamp: timestamp, entityIDs: ["lock.a"]))
   }
   let suggestions = RoutinesSuggester.suggestedRoutines(from: history, now: now, goodnightActionSet: nil)
   #expect(suggestions.isEmpty)
   ```

4. **Test: `testActionSetOrderMatters`**
   ```swift
   // 3 × ["lock.a", "alarm.b"] + 3 × ["alarm.b", "lock.a"] → 0 suggestions (different sets)
   let now = Date()
   var history: [ActionHistoryRecord] = []
   for i in 0..<3 {
       history.append(ActionHistoryRecord(timestamp: now.addingTimeInterval(TimeInterval(-i * 86400)), entityIDs: ["lock.a", "alarm.b"]))
   }
   for i in 3..<6 {
       history.append(ActionHistoryRecord(timestamp: now.addingTimeInterval(TimeInterval(-i * 86400)), entityIDs: ["alarm.b", "lock.a"]))
   }
   let suggestions = RoutinesSuggester.suggestedRoutines(from: history, now: now, goodnightActionSet: nil)
   #expect(suggestions.isEmpty)
   ```

5. **Test: `testMatchesGoodnightKey`**
   ```swift
   // 6 × action-set that matches goodnightActionSet → matchesGoodnightKey = true
   let now = Date()
   let goodnightSet = ["cover.garage", "light.kitchen", "lock.front", "alarm_control_panel.panel"]
   var history: [ActionHistoryRecord] = []
   for i in 0..<6 {
       history.append(ActionHistoryRecord(timestamp: now.addingTimeInterval(TimeInterval(-i * 86400)), entityIDs: goodnightSet))
   }
   let suggestions = RoutinesSuggester.suggestedRoutines(from: history, now: now, goodnightActionSet: goodnightSet)
   #expect(suggestions.count == 1)
   #expect(suggestions.first?.matchesGoodnightKey == true)
   ```

6. **Test: `testPruneHistoryRemovesOldEntries`**
   ```swift
   // Entry at day -15 is pruned, but day -13 is kept
   let now = Date()
   let old = ActionHistoryRecord(timestamp: now.addingTimeInterval(-15 * 86400), entityIDs: ["lock.a"])
   let recent = ActionHistoryRecord(timestamp: now.addingTimeInterval(-13 * 86400), entityIDs: ["lock.b"])
   let pruned = RoutinesSuggester.pruneHistory([old, recent], now: now)
   #expect(pruned.count == 1)
   #expect(pruned.first?.entityIDs == ["lock.b"])
   ```

7. **Test: `testDayPatternWeeknight`**
   ```swift
   // 6 occurrences Mon-Fri → dayPattern = .weeknights
   let calendar = Calendar.current
   let now = Date()
   var history: [ActionHistoryRecord] = []
   for i in 0..<6 {
       let date = calendar.date(byAdding: .day, value: -i, to: now)!
       let weekday = calendar.component(.weekday, from: date)
       if weekday >= 2 && weekday <= 6 {  // Mon-Fri
           history.append(ActionHistoryRecord(timestamp: date, entityIDs: ["lock.a"]))
       }
   }
   let suggestions = RoutinesSuggester.suggestedRoutines(from: history, now: now, goodnightActionSet: nil)
   #expect(suggestions.first?.dayPattern == .weeknights)
   ```

8. **Test: `testHistoryCapAt100Entries`**
   ```swift
   // 101 entries → oldest is evicted
   var history: [ActionHistoryRecord] = []
   for i in 0..<101 {
       history.append(ActionHistoryRecord(timestamp: Date().addingTimeInterval(TimeInterval(-i * 3600)), entityIDs: ["lock.\(i)"]))
   }
   let capped = RoutinesSuggester.record(history: history, newEntry: ActionHistoryRecord(timestamp: Date(), entityIDs: ["lock.new"]))
   #expect(capped.count == 101)  // Max 101 entries, then evict on next
   ```

---

### Task 2: ActionHistoryStore (Shared)

**Files to create:**
- `Shared/ActionHistoryStore.swift`

**Interfaces produced:**
```swift
public enum ActionHistoryStore {
    public static func load(defaults: UserDefaults? = nil) -> [ActionHistoryRecord]
    public static func save(_ history: [ActionHistoryRecord], defaults: UserDefaults? = nil)
    public static func record(entityIDs: [String], defaults: UserDefaults? = nil)
}
```

**Interfaces consumed:**
- `ActionHistoryRecord` (from Task 1)
- `UserDefaults` (App Group suite `group.com.rohit.hearth`)

**TDD steps:**

1. **Test: `testLoadReturnsEmptyForAbsentKey`**
   ```swift
   let defaults = UserDefaults(suiteName: "test.routines")!
   defaults.removeObject(forKey: "routines.history")
   let history = ActionHistoryStore.load(defaults: defaults)
   #expect(history.isEmpty)
   ```

2. **Test: `testSaveAndLoad`**
   ```swift
   let defaults = UserDefaults(suiteName: "test.routines")!
   let entry = ActionHistoryRecord(timestamp: Date(), entityIDs: ["lock.a", "alarm.b"])
   ActionHistoryStore.save([entry], defaults: defaults)
   let loaded = ActionHistoryStore.load(defaults: defaults)
   #expect(loaded.count == 1)
   #expect(loaded.first?.entityIDs == ["lock.a", "alarm.b"])
   ```

3. **Test: `testRecordAppendsAndSaves`**
   ```swift
   let defaults = UserDefaults(suiteName: "test.routines")!
   defaults.removeObject(forKey: "routines.history")
   ActionHistoryStore.record(entityIDs: ["lock.a"], defaults: defaults)
   let loaded = ActionHistoryStore.load(defaults: defaults)
   #expect(loaded.count == 1)
   #expect(loaded.first?.entityIDs == ["lock.a"])
   ```

4. **Test: `testLoadHandlesCorruptData`**
   ```swift
   let defaults = UserDefaults(suiteName: "test.routines")!
   defaults.set(Data([0xFF, 0xFF]), forKey: "routines.history")  // Invalid JSON
   let history = ActionHistoryStore.load(defaults: defaults)
   #expect(history.isEmpty)  // Corrupt → default to empty
   ```

---

### Task 3: Recording Hooks in Runtimes

**Files to modify:**
- `Shared/AlarmActionRuntime.swift`
- `HearthKit/Sources/HearthKit/Goodnight/GoodnightRuntime.swift`
- `Shared/ClimateActionRuntime.swift` (optional — only if climate actions are routinable)

**Changes:**

In `AlarmActionRuntime.perform(...)`, after `.confirmed` outcome:
```swift
case .confirmed:
    _ = try store.finishAlarmOperation(...)
    ActionHistoryStore.record(entityIDs: [entityID])  // NEW
    await notify()
```

In `GoodnightRuntime.run(...)`, after successful execution (all steps done):
```swift
let result = GoodnightResult(...)
if result.garagesClosed && result.lightsOff && result.locked && result.armed {
    let actionSet = config.actionSet(allLights: allLights)
    ActionHistoryStore.record(entityIDs: actionSet)  // NEW
}
return result
```

**TDD steps:**

1. **Test: `testAlarmActionRecordsOnConfirmed`**
   ```swift
   // Mock store + runtime; verify ActionHistoryStore.record() called with correct entityID after .confirmed
   // (Integration test or mock-based unit test)
   ```

2. **Test: `testGoodnightRecordsOnSuccess`**
   ```swift
   // Run GoodnightRuntime.run() with injected success closures
   // Verify ActionHistoryStore has 1 entry with correct actionSet
   let defaults = UserDefaults(suiteName: "test.goodnight.routines")!
   defaults.removeObject(forKey: "routines.history")
   
   let config = GoodnightConfig(enabled: true, startHour: 22, endHour: 6, armMode: .night, keepOnLights: [])
   let haConfig = HaConfig(...) // Mock
   
   let result = await GoodnightRuntime.run(
       config: config,
       haConfig: haConfig,
       now: Date(),
       injectedFetchState: { _ in (["light.kitchen"], true) },
       injectedCloseCover: { _ in },
       injectedTurnOffLights: { _ in },
       injectedLock: { true },
       injectedArm: { _ in true }
   )
   
   let history = ActionHistoryStore.load(defaults: defaults)
   #expect(history.count == 1)
   #expect(history.first?.entityIDs.contains("alarm_control_panel.panel"))
   ```

---

### Task 4: RoutinesPage SwiftUI View

**Files to create:**
- `Hearth/Settings/RoutinesPage.swift`

**Interfaces produced:**
```swift
struct RoutinesPage: View {
    @State private var enabled: Bool
    @State private var routines: [RoutineEntry]
    @State private var showOffConfirm: Bool = false
    
    var body: some View { ... }
}
```

**Interfaces consumed:**
- `ActionHistoryStore.load()`, `.save()`
- `RoutinesSuggester.suggestedRoutines(...)`
- `GoodnightStore.load()`
- `HaConfigStore.load()`
- `HearthGroup`, `HearthRow`, `HearthSwitch`, `HearthColor`, `HearthFont`, `HearthMetrics`

**UI structure (matching mocks):**

1. **Toggle row:**
   - Icon: `arrow.triangle.2.circlepath`, hue: `.purple`
   - Title: "Learn my routines"
   - Subtitle: "Shows a one-tap suggestion on your widget near the usual time"
   - Trailing: `HearthSwitch`

2. **Disclaimer text:**
   - "Never runs on its own. Stays on this phone."
   - Font: `HearthFont.subtitle`, color: `HearthColor.sub`

3. **"Learned" section header** (only when routines exist)

4. **Routine cards:**
   - Big time: `10:30 PM` (use `Date.FormatStyle`)
   - Frequency: `Weeknights · 6 of the last 7`
   - Day pills: `M T W T F S S` (highlighted for active days)
   - Action pills: entity names (e.g., "Kitchen off", "Den off", "Close garage", "Arm night")
   - Appears-on row: "Appears on Home alarm around 10:30 PM"
   - Mapping row: "Same as Goodnight key" (if `matchesGoodnightKey == true`)
   - X button (trailing, top-right) to remove

5. **Learning state** (when enabled && routines.isEmpty):
   - Icon + "Learning..."
   - Text: "A suggestion appears after Hearth sees you do the same steps several times."

6. **Off-confirm dialog** (when toggling off with routines present):
   - Title: "Forget \(routines.count) routine\(routines.count == 1 ? "" : "s")?"
   - Message: "Turning off learning forgets what Hearth learned. You can turn it on again later."
   - Buttons: "Cancel", "Turn off" (destructive)

**TDD steps:**

(SwiftUI views are tested via SwiftUI Previews + manual verification. No unit tests for views, but logic extraction is tested.)

1. **Preview: `RoutinesPage_Enabled_WithRoutines`**
   - Seed: 2 routines (one weeknight, one every day)
   - Verify: toggle on, 2 cards visible, day pills correct

2. **Preview: `RoutinesPage_Enabled_Learning`**
   - Seed: enabled, empty routines
   - Verify: "Learning..." card visible

3. **Preview: `RoutinesPage_Disabled`**
   - Seed: disabled, empty routines
   - Verify: toggle off, no cards

4. **Preview: `RoutinesPage_OffConfirm`**
   - Seed: enabled, 2 routines, showOffConfirm = true
   - Verify: dialog visible with correct count

---

### Task 5: Navigation Wiring

**Files to modify:**
- `HearthKit/Sources/HearthKit/Home/HomeWidgetItem.swift` (add `.routines` case to `HomeRoute`)
- `Hearth/Home/EveryDaySection.swift` (update Routines row to real subtitle + onTap)
- `Hearth/HearthApp.swift` (add `case .routines` handler in `handleHomeRoute`)

**Changes:**

In `HomeRoute`:
```swift
public enum HomeRoute: Sendable, Equatable {
    // ... existing cases
    case routines  // NEW
}
```

In `EveryDaySection.swift`:
```swift
// Replace placeholder row:
Button {
    onTap(.routines)  // Was .settings
} label: {
    HearthRow(
        icon: "arrow.triangle.2.circlepath",
        hue: .purple,
        title: "Routines",
        subtitle: routinesSubtitle  // NEW: "Off" / "On · 2 learned"
    ) {
        HomeChevron()
    }
}

private var routinesSubtitle: String {
    guard HouseFeaturesStore.routinesEnabled else { return "Off" }  // Assumes store added
    let count = suggestedRoutinesCount()
    return count == 0 ? "On" : "On · \(count) learned"
}

private func suggestedRoutinesCount() -> Int {
    let history = ActionHistoryStore.load()
    let goodnightActionSet = GoodnightStore.load().actionSet()
    let routines = RoutinesSuggester.suggestedRoutines(from: history, now: Date(), goodnightActionSet: goodnightActionSet)
    return routines.count
}
```

In `HearthApp.swift` `handleHomeRoute`:
```swift
case .routines:
    presentedSheet = .routines(UUID())
// ...
case routines(let id):
    NavigationStack {
        RoutinesPage()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { presentedSheet = nil }
                }
            }
    }
    .id(id)
```

**TDD steps:**

1. **Manual verification:**
   - Launch app → Home → Every day → Routines → RoutinesPage opens
   - Toggle on → subtitle changes to "On"
   - Execute Goodnight 6 times (via test fixture) → subtitle changes to "On · 1 learned"

---

### Task 6: HouseFeaturesStore Integration

**Files to modify:**
- `Shared/HouseFeaturesStore.swift`

**Changes:**

Add Routines enabled flag:
```swift
public static var routinesEnabled: Bool {
    get { defaults.bool(forKey: "routines.enabled") }
    set { defaults.set(newValue, forKey: "routines.enabled") }
}
```

**TDD steps:**

1. **Test: `testRoutinesEnabledDefaultsFalse`**
   ```swift
   let defaults = UserDefaults(suiteName: "test.features")!
   defaults.removeObject(forKey: "routines.enabled")
   #expect(HouseFeaturesStore.routinesEnabled == false)  // Absent → false
   ```

2. **Test: `testRoutinesEnabledRoundTrip`**
   ```swift
   HouseFeaturesStore.routinesEnabled = true
   #expect(HouseFeaturesStore.routinesEnabled == true)
   ```

---

### Task 7: XcodeGen project.yml Update

**Files to modify:**
- `project.yml`

**Changes:**

Add new files to appropriate groups:
```yaml
Hearth:
  # ... existing
  Settings:
    # ... existing
    - Hearth/Settings/RoutinesPage.swift  # NEW

Shared:
  # ... existing
  - Shared/ActionHistoryStore.swift  # NEW
```

HearthKit package already auto-discovers `Sources/HearthKit/Routines/*.swift`, so no change needed there.

**Verification:**
```bash
xcodegen generate
git diff --exit-code  # Must pass (no untracked changes)
xcodebuild -project Hearth.xcodeproj -scheme Hearth build
```

---

### Task 8: Parity Note & Documentation

**Files to modify:**
- `docs/PARITY-AUDIT.md` (or equivalent)

**Changes:**

Add entry:
```markdown
## Routines

**Status:** ✅ Complete (v1.6.0)

**Android:** Learns action patterns (6+ occurrences in 14 days), suggests one-tap routines. Deterministic frequency suggester, never auto-runs. Stored locally.

**iOS:** Exact parity. `RoutinesSuggester` (HearthKit pure logic) + `ActionHistoryStore` (App Group) + recording hooks in runtimes + RoutinesPage (SwiftUI, matches v2 mocks).

**Differences:** None. Time clustering, day-pattern detection, and Goodnight-key mapping all match Android v2 behavior.

**Tests:** 15 HearthKit unit tests (suggester logic + store), 4 integration tests (runtime hooks), 4 SwiftUI previews.
```

---

## Summary

**Task count:** 8 tasks (models + suggester, store, runtime hooks, SwiftUI page, nav wiring, features store, xcodegen, docs).

**Exact suggester algorithm (extracted):**
- **Threshold:** 6 occurrences of the same action-set (exact entity-ID sequence match, order matters) within a 14-day rolling window.
- **Time window:** 14 days (inferred from "11 of the last 14" in mock).
- **Matching rule:** Exact entity-ID array equality: `["lock.a", "alarm.b"]` ≠ `["alarm.b", "lock.a"]`.
- **Day-pattern:** Tracks occurrences by weekday; labels as "Weeknights" (Mon–Fri majority), "Every day" (all 7 days), or specific days (M T W T F S S pills).
- **Time clustering:** Median time ± 30 min (e.g., 10:28, 10:31, 10:29 → "10:30 PM").
- **Goodnight mapping:** If `routine.entityIDs == GoodnightStore.load().actionSet()`, label "Same as Goodnight key".

**Runtime hook points (iOS):**
1. `AlarmActionRuntime.perform(...)` → after `.confirmed` outcome
2. `GoodnightRuntime.run(...)` → after all 4 steps succeed
3. `ClimateActionRuntime` (optional — only if climate actions are part of routines)

**Genuine ambiguities requiring owner decision:**

1. **Should climate actions (thermostat changes) be included in routines?** The mocks only show alarm/lock/lights/garage. Android behavior unclear. **Recommendation:** Start with alarm/lock/lights/garage only (Phase 5 scope), defer climate to Phase 6 polish if requested.

2. **What happens to a "Same as Goodnight key" routine if Goodnight is later disabled or its action-set changes?** Options:
   - A) Keep the routine, remove the "Same as..." label (show generic name).
   - B) Auto-remove the routine (forgetting it).
   - C) Show a "Key changed" state.
   **Recommendation:** Option A (keep routine, remove label) — simplest, preserves user data, matches "never auto-run" philosophy.

3. **Should the routine suggestion appear on the widget itself, or only in Settings?** The mock text says "Shows a one-tap suggestion on your widget near the usual time," but the iOS widget-reload mechanism is WidgetKit timeline-based. **Recommendation:** Phase 5 shows routines only in RoutinesPage (Settings); Phase 6 adds widget suggestions via WidgetKit timeline entries (separate PR).

4. **Exact median-time clustering tolerance:** Assumed ±30 min. If Android uses a different value, adjust `RoutinesSuggester` clustering logic. **Recommendation:** Start with ±30 min, verify against Android after build.

---

## Controller Rulings (2026-11-26) — resolve the flagged ambiguities

These are decided within the approved Phase-5 scope + the "match Android" principle; no owner input required.

1. **Climate actions — EXCLUDED.** Record only alarm / lock / lights / garage action-sets (Phase 5 scope). Climate is out until a later phase.
2. **Deleted/changed Goodnight key — keep the routine, drop the label.** If the Goodnight key is disabled or its action-set no longer matches, the suggested routine must NOT crash: show it with a generic name (no "Same as Goodnight key" label). Already covered by Review Focus #4 — ensure the test asserts it.
3. **Widget suggestions — DEFERRED to Phase 6.** Phase 5 Routines is Settings-only (the RoutinesPage). No widget surface yet.
4. **Threshold / window / clustering are PROVISIONAL — source-diff Android in Task 1.** The 6-occurrences / 14-day / ±30-min-median values were ASSUMED, not confirmed. Task 1 MUST read the Android Routines implementation (hearth-worktrees/routines-renders + main Android repo) and use Android's ACTUAL values; the provisional numbers are a fallback only if Android has no explicit constant. (Cf. the 5a lesson: diff Android, never guess the behavior.)
5. **Task 7 (project.yml) is likely a NO-OP.** `project.yml` references source DIRECTORIES (`Shared`, `Hearth`) and the HearthKit SPM package auto-globs `Sources/HearthKit/**`. Adding files to existing roots needs no project.yml edit (confirmed by Phase 5c's file moves). Keep Task 7 only as a `xcodegen generate && git diff --exit-code` gate check; if it shows no diff, the task is a no-op — do NOT hand-edit project.yml to add individual files.

**EXECUTION GATE:** do not begin executing this plan until the owner has validated build 13's UX direction (the RoutinesPage reuses the same Settings-page patterns the owner questioned). Tasks 1–3 (suggester logic, ActionHistoryStore, runtime hooks) are UX-independent and safe to start early if forward motion is needed; Tasks 4–6 (page + nav) should wait for that validation.
