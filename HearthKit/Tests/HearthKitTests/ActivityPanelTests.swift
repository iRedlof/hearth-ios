import Testing
import Foundation
@testable import HearthKit

private let unreachable = "Can't reach Home Assistant"

@Suite("Activity two-panel")
struct ActivityPanelTests {
    private let now = Date(timeIntervalSince1970: 1_793_354_400)   // 2026-10-30 10:00 UTC
    private let utc = TimeZone(identifier: "UTC") ?? .gmt
    private let posix = Locale(identifier: "en_US_POSIX")

    private func item(_ minutesAgo: Double, _ kind: ActivityKind, _ name: String, _ action: String,
                      by: String? = nil) -> ActivityItem {
        ActivityItem(at: now.addingTimeInterval(-minutesAgo * 60), kind: kind, text: "\(name) \(action)", by: by,
                     entityId: "x.\(name)", name: name, action: action, eventKey: "\(name)|\(action)")
    }
    private var five: [ActivityItem] {
        [item(5, .garage, "Garage", "closed", by: "Ring Armed & Home routine"), item(30, .alarm, "Home Alarm", "disarmed"),
         item(60, .lock, "Front Door", "unlocked"), item(105, .door, "Back Door", "opened"),
         item(150, .charge, "Tesla", "plugged in")]
    }
    private func panel(_ snap: ActivitySnapshot) -> ActivityPanel {
        activityPanel(snap, now: now, zone: utc, locale: posix)
    }

    @Test("The rail is the latest event; the body is what came before it")
    func ready() {
        let result = panel(ActivitySnapshot(items: five, checkedAt: "10:00 AM"))
        #expect(result.rail == PanelRail(icon: "door.garage.closed", word: "Garage", detail: "closed\n9:55 AM", tone: .unknown))
        #expect(result.rows.map(\.text) == ["Home Alarm disarmed", "Front Door unlocked", "Back Door opened", "Tesla plugged in"])
        #expect(result.rows.map(\.time) == ["9:30 AM", "9:00 AM", "8:15 AM", "7:30 AM"])
        #expect(result.rows.map(\.icon) == ["shield.fill", "lock.fill", "door.left.hand.closed", "bolt.fill"])
        #expect(result.prompt == nil)
        #expect(result.note == nil)
        #expect(result.checked == "10:00 AM")
        let page = panelPage(result.rows, limit: PanelLimits.maxRows)
        #expect(page.shown.count == 3)
        #expect(page.moreLabel == "+1 more")
    }

    @Test("Activity only informs: its rail is always neutral")
    func neutral() {
        #expect(panel(ActivitySnapshot(items: [item(5, .alarm, "Home Alarm", "triggered")], checkedAt: "")).rail.tone == .unknown)
    }

    @Test("Rows have distinct identities even when two events share a key")
    func identities() {
        let twins = [item(5, .garage, "Garage", "closed"), item(6, .garage, "Garage", "opened"), item(6, .garage, "Garage", "opened")]
        let rows = panel(ActivitySnapshot(items: twins, checkedAt: "")).rows
        #expect(Set(rows.map(\.id)).count == rows.count)
    }

    @Test("One event alone says nothing else happened")
    func single() {
        let result = panel(ActivitySnapshot(items: [five[0]], checkedAt: "10:00 AM"))
        #expect(result.rail.word == "Garage")
        #expect(result.rows.isEmpty)
        #expect(result.note == "Nothing else recent")
        #expect(result.prompt == nil)
    }

    @Test("Events older than a day are left out")
    func window() {
        let old = item(25 * 60, .lock, "Front Door", "locked")
        let result = panel(ActivitySnapshot(items: [five[0], old], checkedAt: "10:00 AM"))
        #expect(result.rows.isEmpty)
        let quiet = panel(ActivitySnapshot(items: [old], checkedAt: "10:00 AM", state: .empty))
        #expect(quiet.rail == PanelRail(icon: "clock.arrow.circlepath", word: "Quiet", detail: "No recent events", tone: .unknown))
        #expect(quiet.prompt == PanelPrompt(message: "No recent activity", action: nil))
    }

    @Test("Unreachable keeps the last-known events and says why")
    func failed() {
        let result = panel(ActivitySnapshot(items: five, checkedAt: "8:00 AM", state: .failed, error: unreachable))
        #expect(result.rail.word == "Garage")
        #expect(result.rail.tone == .unknown)
        #expect(result.notice == unreachable)
        #expect(result.rows.count == 4)
        #expect(result.checked == "8:00 AM")
        let nothing = panel(ActivitySnapshot(items: [], checkedAt: "", state: .failed, error: unreachable))
        #expect(nothing.rail == PanelRail(icon: "clock.arrow.circlepath", word: "Can't read", detail: "Home is unreachable", tone: .unknown))
        #expect(nothing.prompt == PanelPrompt(message: unreachable, action: nil))
    }

    @Test("Not set up and loading")
    func prompts() {
        let setup = panel(ActivitySnapshot(items: [], checkedAt: "", state: .setup))
        #expect(setup.rail == panelSetupRail(icon: "clock.arrow.circlepath"))
        #expect(setup.prompt == PanelPrompt(message: "Connect Home Assistant", action: .connect))
        #expect(panel(.loading).rail == panelCheckingRail(icon: "clock.arrow.circlepath"))
    }

    @Test("An older cached event with one label still splits into name and action")
    func legacy() {
        let legacy = ActivityItem(at: now.addingTimeInterval(-300), kind: .lock, text: "Front Door locked", by: nil)
        let result = panel(ActivitySnapshot(items: [legacy, legacy], checkedAt: ""))
        #expect(result.rail.word == "Front Door")
        #expect(result.rail.detail == "locked\n9:55 AM")
        #expect(result.rows.map(\.text) == ["Front Door locked"])
    }

    @Test("Each kind of event has its glyph")
    func icons() {
        #expect(activityIcon(.alarm) == "shield.fill")
        #expect(activityIcon(.lock) == "lock.fill")
        #expect(activityIcon(.carLock) == "car.fill")
        #expect(activityIcon(.garage) == "door.garage.closed")
        #expect(activityIcon(.door) == "door.left.hand.closed")
        #expect(activityIcon(.charge) == "bolt.fill")
    }
}
