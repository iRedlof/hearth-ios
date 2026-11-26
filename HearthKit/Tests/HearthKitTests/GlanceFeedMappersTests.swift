import Testing
import Foundation
@testable import HearthKit

@Suite("GlanceFeed Mappers")
struct GlanceFeedMappersTests {

    // MARK: - Car Mapper Tests

    @Test("Car error state produces error feed")
    func carErrorProducesErrorFeed() {
        let snapshot = CarSnapshot(
            name: "Car", checkedAt: "9:41", battery: nil, range: "—",
            lock: "—", lockWarn: false, doors: "—", doorsWarn: false,
            cabin: "—", outside: "—", tires: "—", tiresWarn: false,
            place: "—", sentry: .unknown, chargeLine: "—", tone: .blue,
            error: "Connection failed"
        )

        let feed = glanceFeed(from: snapshot, checkedAt: .now)

        #expect(feed.kind == HomeWidgetKind.car)
        #expect(feed.error == true)
        #expect(feed.items.isEmpty)
        #expect(feed.calm == false)
    }

    @Test("Car locked and closed is calm")
    func carLockedAndClosedIsCalm() {
        let snapshot = CarSnapshot(
            name: "Car", checkedAt: "9:41", battery: 72, range: "219 mi",
            lock: "Locked", lockWarn: false, doors: "All shut", doorsWarn: false,
            cabin: "68°F", outside: "52°F", tires: "38 psi", tiresWarn: false,
            place: "Home", sentry: .off, chargeLine: "Unplugged", tone: .mint
        )

        let feed = glanceFeed(from: snapshot, checkedAt: .now)

        #expect(feed.kind == HomeWidgetKind.car)
        #expect(feed.error == false)
        #expect(feed.items.isEmpty)
        #expect(feed.calm == true)
    }

    @Test("Car low battery warns")
    func carLowBatteryWarns() {
        let snapshot = CarSnapshot(
            name: "Car", checkedAt: "9:41", battery: 15, range: "45 mi",
            lock: "Locked", lockWarn: false, doors: "All shut", doorsWarn: false,
            cabin: "68°F", outside: "52°F", tires: "38 psi", tiresWarn: false,
            place: "Home", sentry: .off, chargeLine: "Unplugged", tone: .red
        )

        let feed = glanceFeed(from: snapshot, checkedAt: .now)

        #expect(feed.kind == HomeWidgetKind.car)
        #expect(feed.error == false)
        #expect(feed.calm == false)
        #expect(feed.items.count == 1)
        #expect(feed.items[0].text.contains("battery"))
        #expect(feed.items[0].severity == .warn)
    }

    @Test("Car unlocked warns")
    func carUnlockedWarns() {
        let snapshot = CarSnapshot(
            name: "Car", checkedAt: "9:41", battery: 72, range: "219 mi",
            lock: "Unlocked", lockWarn: true, doors: "All shut", doorsWarn: false,
            cabin: "68°F", outside: "52°F", tires: "38 psi", tiresWarn: false,
            place: "Home", sentry: .off, chargeLine: "Unplugged", tone: .orange
        )

        let feed = glanceFeed(from: snapshot, checkedAt: .now)

        #expect(feed.kind == HomeWidgetKind.car)
        #expect(feed.error == false)
        #expect(feed.calm == false)
        #expect(feed.items.count >= 1)
        #expect(feed.items.contains { $0.text.lowercased().contains("unlocked") })
        #expect(feed.items.allSatisfy { $0.severity == .warn })
    }

    @Test("Car doors open warns")
    func carDoorsOpenWarns() {
        let snapshot = CarSnapshot(
            name: "Car", checkedAt: "9:41", battery: 72, range: "219 mi",
            lock: "Locked", lockWarn: false, doors: "2 open", doorsWarn: true,
            cabin: "68°F", outside: "52°F", tires: "38 psi", tiresWarn: false,
            place: "Home", sentry: .off, chargeLine: "Unplugged", tone: .orange
        )

        let feed = glanceFeed(from: snapshot, checkedAt: .now)

        #expect(feed.kind == HomeWidgetKind.car)
        #expect(feed.error == false)
        #expect(feed.calm == false)
        #expect(feed.items.count >= 1)
        #expect(feed.items.contains { $0.text.contains("2 open") })
        #expect(feed.items.allSatisfy { $0.severity == .warn })
    }

    // MARK: - Alarm Mapper Tests

    @Test("Alarm error state produces error feed")
    func alarmErrorProducesErrorFeed() {
        var snapshot = AlarmSnapshot.sample
        snapshot.error = "Connection failed"

        let feed = glanceFeed(from: snapshot, checkedAt: .now)

        #expect(feed.kind == HomeWidgetKind.alarm)
        #expect(feed.error == true)
        #expect(feed.items.isEmpty)
        #expect(feed.calm == false)
    }

    @Test("Alarm triggered produces alarm severity")
    func alarmTriggeredProducesAlarmSeverity() {
        var snapshot = AlarmSnapshot.sample
        snapshot.stateWord = "Alarm triggered"
        snapshot.detail = "Front door 2 min ago"
        snapshot.tone = .red

        let feed = glanceFeed(from: snapshot, checkedAt: .now)

        #expect(feed.kind == HomeWidgetKind.alarm)
        #expect(feed.error == false)
        #expect(feed.calm == false)
        #expect(feed.items.count >= 1)
        #expect(feed.items[0].text.contains("triggered"))
        #expect(feed.items[0].severity == .alarm)
    }

    @Test("Alarm disarmed with locked door is calm")
    func alarmDisarmedWithLockedDoorIsCalm() {
        var snapshot = AlarmSnapshot.sample
        snapshot.stateWord = "Disarmed"
        snapshot.doorLocked = true
        snapshot.doorState = "Locked"

        let feed = glanceFeed(from: snapshot, checkedAt: .now)

        #expect(feed.kind == HomeWidgetKind.alarm)
        #expect(feed.error == false)
        #expect(feed.calm == true)
        #expect(feed.items.isEmpty)
    }

    @Test("Alarm disarmed with unlocked door warns")
    func alarmDisarmedWithUnlockedDoorWarns() {
        var snapshot = AlarmSnapshot.sample
        snapshot.stateWord = "Disarmed"
        snapshot.doorLocked = false
        snapshot.doorState = "Unlocked"
        snapshot.doorName = "Front Door"

        let feed = glanceFeed(from: snapshot, checkedAt: .now)

        #expect(feed.kind == HomeWidgetKind.alarm)
        #expect(feed.error == false)
        #expect(feed.calm == false)
        #expect(feed.items.count == 1)
        #expect(feed.items[0].text.contains("unlocked"))
        #expect(feed.items[0].severity == .warn)
    }

    // MARK: - Doors Mapper Tests

    @Test("Doors error state produces error feed")
    func doorsErrorProducesErrorFeed() {
        let summary = DoorsSummary(
            headline: "Error",
            tone: .unknown,
            lockLine: nil,
            rows: []
        )
        let snapshot = DoorsSnapshot(summary: summary, checkedAt: "9:41", error: "Connection failed")

        let feed = glanceFeed(from: snapshot, checkedAt: .now)

        #expect(feed.kind == HomeWidgetKind.doors)
        #expect(feed.error == true)
        #expect(feed.items.isEmpty)
        #expect(feed.calm == false)
    }

    @Test("Doors all closed is calm")
    func doorsAllClosedIsCalm() {
        let summary = DoorsSummary(
            headline: "All secure",
            tone: .calm,
            lockLine: nil,
            rows: [
                DoorView(id: "lock.front", name: "Front Door", status: "Locked", open: false, action: nil),
                DoorView(id: "cover.garage", name: "Garage", status: "Closed", open: false, action: nil)
            ]
        )
        let snapshot = DoorsSnapshot(summary: summary, checkedAt: "9:41")

        let feed = glanceFeed(from: snapshot, checkedAt: .now)

        #expect(feed.kind == HomeWidgetKind.doors)
        #expect(feed.error == false)
        #expect(feed.calm == true)
        #expect(feed.items.isEmpty)
    }

    @Test("Doors with open door warns")
    func doorsWithOpenDoorWarns() {
        let summary = DoorsSummary(
            headline: "1 open",
            tone: .warn,
            lockLine: nil,
            rows: [
                DoorView(id: "lock.front", name: "Front Door", status: "Locked", open: false, action: nil),
                DoorView(id: "cover.garage", name: "Garage", status: "Open", open: true, action: nil)
            ]
        )
        let snapshot = DoorsSnapshot(summary: summary, checkedAt: "9:41")

        let feed = glanceFeed(from: snapshot, checkedAt: .now)

        #expect(feed.kind == HomeWidgetKind.doors)
        #expect(feed.error == false)
        #expect(feed.calm == false)
        #expect(feed.items.count == 1)
        #expect(feed.items[0].text.contains("Garage"))
        #expect(feed.items[0].text.lowercased().contains("open"))
        #expect(feed.items[0].severity == .warn)
    }

    @Test("Doors with unlocked door warns")
    func doorsWithUnlockedDoorWarns() {
        let summary = DoorsSummary(
            headline: "1 unlocked",
            tone: .warn,
            lockLine: nil,
            rows: [
                DoorView(id: "lock.front", name: "Front Door", status: "Unlocked", open: false, action: nil),
                DoorView(id: "cover.garage", name: "Garage", status: "Closed", open: false, action: nil)
            ]
        )
        let snapshot = DoorsSnapshot(summary: summary, checkedAt: "9:41")

        let feed = glanceFeed(from: snapshot, checkedAt: .now)

        #expect(feed.kind == HomeWidgetKind.doors)
        #expect(feed.error == false)
        #expect(feed.calm == false)
        #expect(feed.items.count == 1)
        #expect(feed.items[0].text.contains("Front Door"))
        #expect(feed.items[0].text.lowercased().contains("unlocked"))
        #expect(feed.items[0].severity == .warn)
    }

    // MARK: - ChargePoint Mapper Tests

    @Test("ChargePoint calm state")
    func chargePointCalmState() {
        let snapshot = CpSnapshot(
            site: "SEA41", account: "user", bigAnswer: "12", unit: "plugs free",
            sub: "7.4 kW", plugsFree: "12 of 86", autoOn: false,
            actionLabel: "Open", keys: []
        )

        let feed = glanceFeed(from: snapshot, checkedAt: .now)

        #expect(feed.kind == HomeWidgetKind.chargePoint)
        #expect(feed.error == false)
        #expect(feed.calm == true)
        #expect(feed.items.isEmpty)
    }

    @Test("ChargePoint your turn needs action")
    func chargePointYourTurnNeedsAction() {
        let snapshot = CpSnapshot(
            site: "SEA41", account: "user", bigAnswer: "Your turn", unit: "",
            sub: "Respond now", plugsFree: nil, autoOn: true,
            actionLabel: "Open", keys: [
                CpKey(command: "accept", label: "Accept"),
                CpKey(command: "snooze", label: "Snooze")
            ],
            deadline: Date().addingTimeInterval(165)
        )

        let feed = glanceFeed(from: snapshot, checkedAt: .now)

        #expect(feed.kind == HomeWidgetKind.chargePoint)
        #expect(feed.error == false)
        #expect(feed.calm == false)
        #expect(feed.items.count >= 1)
        #expect(feed.items[0].text.contains("Your turn"))
        #expect(feed.items[0].severity == .act)
    }

    @Test("ChargePoint with rail notes warns")
    func chargePointWithRailNotesWarns() {
        let snapshot = CpSnapshot(
            site: "SEA41", account: "user", bigAnswer: "Charging", unit: "",
            sub: "7.4 kW", plugsFree: nil, autoOn: false,
            actionLabel: "Open", keys: [],
            railNotes: ["Move by 10:14 AM"]
        )

        let feed = glanceFeed(from: snapshot, checkedAt: .now)

        #expect(feed.kind == HomeWidgetKind.chargePoint)
        #expect(feed.error == false)
        #expect(feed.calm == false)
        #expect(feed.items.count == 1)
        #expect(feed.items[0].text.contains("Move by"))
        #expect(feed.items[0].severity == .warn)
    }
}

