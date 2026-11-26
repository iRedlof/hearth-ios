#if DEBUG
import Foundation
import WidgetKit
import HearthKit
import OSLog

/// DEBUG isolation is selected synchronously before any ordinary config/runtime initialization.
enum CarRouteProbe {
    static let buildMarker = CarRouteProbeBuild.marker
    static let isolationKey = "carRouteProbeIsolationRequired.v1"
    static let widgetKinds = ["com.rohit.hearth.car-readings-probe-a", "com.rohit.hearth.car-readings-probe-b"]
    private static let logger = Logger(subsystem: "com.rohit.hearth", category: "DEBUGCarRouteProbe")

    private static func controlStore() -> CarRouteProbeControlStore? {
        guard let group = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: HaConfigStore.appGroup) else { return nil }
        return CarRouteProbeControlStore(root: group.appendingPathComponent(
            "Library/Application Support/CarRouteProbe", isDirectory: true))
    }

    /// An explicit selector establishes sticky local isolation even if arming cannot finish.
    static func resolveLaunch(arguments: [String]) -> CarRouteProbeSelection {
        if arguments.contains("-carWidgetProbe") {
            requireIsolation()
            guard let scenario = CarRouteProbeLaunchResolver.scenario(arguments: arguments) else {
                return reported(.blocked("The DEBUG Car probe scenario is missing or invalid."))
            }
            return arm(scenario: scenario)
        }
        return selection()
    }

    static func selection() -> CarRouteProbeSelection {
        let required = UserDefaults.standard.bool(forKey: isolationKey)
        guard let control = controlStore() else {
            return required ? reported(.blocked("The DEBUG Car probe App Group cannot be opened.")) : .inactive
        }
        let record = control.read()
        if record != .absent { requireIsolation() }
        let selected = CarRouteProbeLaunchResolver.resolve(arguments: [], isolationRequired: required, control: record)
        if case .armed(let run) = selected {
            // Never let a disappeared state file be recreated with default/empty private state.
            guard (try? FileManager.default.attributesOfItem(atPath: control.runDirectory(run)
                .appendingPathComponent("HA/ha-state.json").path)[.type] as? FileAttributeType) == .typeRegular else {
                return reported(.blocked("The controlled Home Assistant state cannot be opened. Arm a new run."))
            }
        }
        return reported(selected)
    }

    /// Arming only creates a private HA state. Real provider work owns envelope/ticket issuance.
    @discardableResult static func arm(scenario: CarRouteProbeScenario) -> CarRouteProbeSelection {
        requireIsolation()
        // The DEBUG parity key is inspected without production config or a defaults fallback.
        guard UserDefaults(suiteName: HaConfigStore.appGroup)?.dictionary(forKey: "parityWidgetSelection") == nil else {
            return reported(.blocked("A DEBUG parity capture is active. Explicitly leave parity before arming the Car probe."))
        }
        guard let control = controlStore() else {
            return reported(.blocked("The DEBUG Car probe App Group cannot be opened."))
        }
        do {
            let run = try CarRouteProbeRun(runID: UUID(), generation: UUID(), scenario: scenario, fixtureClock: .now)
            try control.seedAndActivate(run)
            let writer = try receipts(run: run)
            writer.record(phase: "armed", fields: ["controlledResult": "privateStatePreparedNoTicket"])
            reloadWidgets()
            return .armed(run)
        } catch {
            return reported(.blocked("The private DEBUG Car probe could not be armed. Controlled isolation remains active."))
        }
    }

    static func dependencies(run: CarRouteProbeRun, slot: CarRouteProbeSlot) throws -> CarRouteProbeDependencies {
        guard let control = controlStore() else { throw CarRouteProbeStorageError.invalid }
        return try CarRouteProbeDependencies(run: run, slot: slot, control: control)
    }

    /// Receipt/render access cannot initialize state, fetch transport, or open the ticket store.
    static func receipts(run: CarRouteProbeRun, slot: CarRouteProbeSlot? = nil) throws -> CarRouteProbeReceiptWriter {
        guard let control = controlStore(), control.isCurrent(run) else { throw CarRouteProbeStorageError.invalid }
        return CarRouteProbeReceiptWriter(run: run, slot: slot,
            directory: control.runDirectory(run).appendingPathComponent("Receipts", isDirectory: true))
    }
    static func allowsPublication(run: CarRouteProbeRun) -> Bool {
        controlStore()?.isCurrent(run) == true
    }

    @discardableResult static func disarm() -> CarRouteProbeSelection {
        requireIsolation()
        do { guard let control = controlStore() else { throw CarRouteProbeStorageError.invalid }
            try control.disable()
            reloadWidgets()
            return reported(.blocked("The DEBUG Car probe is disabled. Remove its widgets before explicitly resetting isolation."))
        } catch { return reported(.blocked("The DEBUG Car probe could not be disabled. Isolation remains active.")) }
    }

    /// A separate, explicit harness action after the tester has removed both probe widgets.
    /// It is never called from startup or from disarm.
    static func resetIsolationAfterRemovingProbeWidgets() throws {
        guard let control = controlStore(), control.read() == .disabled else { throw CarRouteProbeStorageError.invalid }
        let file = control.root.appendingPathComponent("control.json")
        try FileManager.default.removeItem(at: file)
        UserDefaults.standard.removeObject(forKey: isolationKey)
        UserDefaults.standard.synchronize()
    }

    /// DEBUG harness controls use only the captured private run and validated request UUID.
    static func setRefreshBarrier(run: CarRouteProbeRun, held: Bool) throws {
        guard let control = controlStore() else { throw CarRouteProbeStorageError.invalid }
        try control.setRefreshBarrier(run: run, held: held)
    }
    static func releaseRequest(run: CarRouteProbeRun, requestID: UUID) throws {
        guard let control = controlStore() else { throw CarRouteProbeStorageError.invalid }
        try control.releaseRequest(run: run, requestID: requestID)
    }

    /// Explicit harness reload only. The screen's reload callback never calls WidgetCenter.
    static func reloadWidgets() {
        for kind in widgetKinds { WidgetCenter.shared.reloadTimelines(ofKind: kind) }
    }
    static func selectorConflict(arguments: [String]) -> String? {
        let other = ["-carRouteFixture", "-parityState", "-parityLive", "-settingsFixture", "-accessibleFixture"]
        return arguments.contains(where: other.contains)
            ? "DEBUG probe isolation overrides other fixture/parity selectors." : nil
    }
    private static func requireIsolation() {
        UserDefaults.standard.set(true, forKey: isolationKey)
        UserDefaults.standard.synchronize()
    }
    static func recordBlocked(reason: String, run: CarRouteProbeRun? = nil) {
        if let run, let writer = try? receipts(run: run) {
            writer.record(phase: "blocked", fields: ["reason": reason])
        }
        // An unreadable group/manifest has no validated run identity to attach to a private receipt.
        logger.notice("DEBUG Car probe blocked: \(reason, privacy: .public)")
    }
    private static func reported(_ selection: CarRouteProbeSelection) -> CarRouteProbeSelection {
        if case .blocked(let reason) = selection { recordBlocked(reason: reason) }
        return selection
    }
}
#endif
