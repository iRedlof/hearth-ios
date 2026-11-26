#if DEBUG
import SwiftUI
import UIKit
import AppIntents
import HearthKit

/// A private native integration fixture. Commands invoke the real intent methods in this process.
/// The card is the production view at an explicitly declared reference size, not a WidgetKit host.
struct CpOwnedNativeHost: View {
    @StateObject private var model = CpOwnedNativeModel()
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("ChargePoint owned intents").font(.title2.bold())
                    Text(model.caseName).font(.headline).accessibilityIdentifier("cp.native.case")
                    Text("In-process intents · 364 × 170 pt reference").font(.subheadline).foregroundStyle(.secondary)
                    CpBeaconView(model.display)
                        .frame(width: 364, height: 170)
                        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                        .allowsHitTesting(false)
                        .frame(maxWidth: .infinity)
                    Text("Card controls are visual here. The buttons below invoke the actual iOS intent methods.")
                        .font(.footnote).foregroundStyle(.secondary)
                    Button("Run \(model.caseName)") { Task { await model.run() } }
                        .buttonStyle(.borderedProminent).disabled(model.running || model.finished)
                        .accessibilityIdentifier("cp.native.run")
                    Text(model.summary).font(.body).accessibilityIdentifier("cp.native.status")
                    if model.finished {
                        Text(model.passed ? "SETTLED · PASS" : "SETTLED · FAIL")
                            .font(.headline).foregroundStyle(model.passed ? .green : .red)
                            .accessibilityIdentifier("cp.native.settled")
                    }
                    if model.showSetup {
                        SettingsSetupScreen(route: .cpSignIn, runtime: LiveSettingsRuntime.shared,
                            cpOrigin: model.settingsOrigin, onComplete: {})
                            .frame(height: 150)
                    }
                }.padding(22)
            }.background(Color(uiColor: .systemGroupedBackground))
        }.task {
            if ProcessInfo.processInfo.arguments.contains("--cp-owned-native-run") { await model.run() }
        }
    }
}

@MainActor private final class CpOwnedNativeModel: ObservableObject {
    static let cases: Set<String> = ["setup-isolation", "manual-join", "explicit-join", "resume-spent",
        "lost-response-pause", "snooze-pause", "retired-replaced", "discarded-dependencies", "held-spent"]
    let caseName: String
    @Published var display = CpSessionStore.unavailableSnapshot
    @Published var summary = "Ready"
    @Published var running = false
    @Published var finished = false
    @Published var passed = false
    @Published var showSetup = false
    var settingsOrigin: CpSettingsOrigin?
    private var directory: URL?
    private var suiteName: String?
    private var store: CpStateStore?
    private let ledger = CpNativeLedger()
    private var checks: [[String: Any]] = []
    private var snapshots: [[String: Any]] = []

    init() {
        let args = ProcessInfo.processInfo.arguments
        if let index = args.firstIndex(of: "--cp-owned-native-case"), index + 1 < args.count { caseName = args[index + 1] }
        else { caseName = "invalid" }
    }

    private func check(_ name: String, _ condition: Bool) { checks.append(["name": name, "passed": condition]) }
    private func snapshot(_ name: String, _ value: CpStoreSnapshot) {
        snapshots.append(["name": name, "state": CpNativeLedger.state(value)])
    }
    private func origin(_ value: CpStoreSnapshot) throws -> String {
        let encoded = CpSessionStore.encodedActionOrigin(value.renderedOrigin)
        guard !encoded.isEmpty else { throw CpFeedback.detailsChanged }
        return encoded
    }

    func run() async {
        guard !running, !finished else { return }
        running = true; summary = "Running actual intent methods…"
        do {
            guard CpSessionStore.fixtureActive, Self.cases.contains(caseName) else { throw CpFeedback.unavailable }
            let name = "cp-owned-native-" + UUID().uuidString
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(name, isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
            self.directory = directory; suiteName = name
            let store = CpStateStore(directory: directory); self.store = store
            let transport = CpNativeTransport(ledger: ledger, stationNames: caseName == "held-spent"
                ? [1: "SEA41 SEA41-29 P3", 2: "SEA41 SEA41-7 P2"] : [:])
            let armed = ["lost-response-pause", "snooze-pause"].contains(caseName)
            let spent = ["resume-spent", "held-spent"].contains(caseName)
            let run = CpRun(armed: armed, snoozeUsed: spent, startedAt: 7)
            let location = CpLocation(name: "Amazon Day 1", address: "Native fixture address", deviceIds: [1, 2],
                bounds: cpBounds(lat: 47.6, lon: -122.3))
            let initial = try store.bootstrap(legacy: CpLegacyState(
                session: CpSession(token: "inert-native-cookie", userId: 17, email: "native@example.invalid"),
                location: location, runWire: cpRunToWire(run), udid: "inert-native-device"))
            try CpSessionStore.installFixture(CpOwnedFixtureDependencies(directory: directory, suiteName: name,
                transport: transport, now: { .now },
                onAlert: { [ledger] alert, state in ledger.effect("alert", fields: ["alert": String(describing: alert), "state": CpNativeLedger.state(state)]) },
                onReload: { [ledger] in ledger.effect("reload") },
                onPermission: { [ledger] in ledger.effect("permission") }))
            SettingsEffectAudit.record = { [ledger] effect in ledger.effect("settings." + effect) }
            settingsOrigin = initial.settingsOrigin
            let runtime = try CpSessionStore.runtime()
            if caseName == "setup-isolation" {
                snapshot("before", initial)
                let cpSignIn = LiveSettingsRuntime.shared.openSetupRoute(.cpSignIn)
                let cpLocation = LiveSettingsRuntime.shared.openSetupRoute(.cpLocation)
                let ha = LiveSettingsRuntime.shared.openSetupRoute(.haSignIn)
                if case .fixture = cpSignIn { check("CP Sign-in never constructs live WebKit", true) }
                else { check("CP Sign-in never constructs live WebKit", false) }
                if case .fixture = cpLocation { check("CP Location never constructs live MapKit", true) }
                else { check("CP Location never constructs live MapKit", false) }
                if case .live = ha { check("HA route is preserved", true) } else { check("HA route is preserved", false) }
                showSetup = checks.allSatisfy { $0["passed"] as? Bool == true }
            } else {
                if caseName == "resume-spent" { transport.phase = "WAITING" }
                if ["snooze-pause", "held-spent"].contains(caseName) { transport.phase = "PENDING_PLUG_IN" }
                if caseName == "retired-replaced" { transport.phase = "ACCEPT_PENDING" }
                _ = try await runtime.refresh(runAuto: false)
                let before = try store.snapshot(); snapshot("before", before)
                let encoded = try origin(before)
                switch caseName {
                case "held-spent":
                    let projected = try before.displaySnapshot()
                    check("Local spent history is retained", before.run.snoozeUsed && !before.run.armed)
                    check("Provider remaining allowance remains unmodified", before.reading?.provider.snoozesLeft == 1)
                    check("Held caption reports the local completed snooze", projected.railNotes.contains("Snooze used") && !projected.railNotes.contains("1 snooze left"))
                    if case let .inLine(_, phase, _, offer?, _) = before.reading?.provider.waitlist {
                        check("Typed Held identity and countdown are retained",
                            phase == "PENDING_PLUG_IN" && offer.deviceId == 1 && offer.port == 1 && projected.deadline != nil)
                    } else { check("Typed Held identity and countdown are retained", false) }
                    check("Assignment projection supplies the visible level and charger",
                        projected.goTo == "SEA41-29 P3" && cpLevelOf(projected.goTo ?? "") == "P3"
                            && cpChargerShort(projected.goTo ?? "") == "SEA41-29")
                    check("Rendering sends no mutation", ledger.mutations == 0)
                case "manual-join":
                    ledger.effect("intent", fields: ["type": "CpJoinIntent", "action": "join"])
                    _ = try await CpJoinIntent(origin: encoded).perform()
                    let after = try store.snapshot()
                    check("Manual Join sends one mutation", ledger.mutations == 1)
                    check("Manual Join keeps Auto off", !after.run.armed)
                    check("Manual Join requests no permission", ledger.count("permission") == 0)
                case "explicit-join":
                    ledger.effect("intent", fields: ["type": "CpControlIntent", "action": "join"])
                    _ = try await CpControlIntent("join", origin: encoded).perform()
                    ledger.effect("intent", fields: ["type": "CpControlIntent", "action": "duplicate old join"])
                    _ = try await CpControlIntent("join", origin: encoded).perform()
                    let after = try store.snapshot()
                    check("Explicit Join sends only one mutation", ledger.mutations == 1)
                    check("Explicit Join arms Auto", after.run.armed)
                    check("Only accepted current mode requests permission", ledger.count("permission") == 1)
                case "resume-spent":
                    ledger.effect("intent", fields: ["type": "CpControlIntent", "action": "resume"])
                    _ = try await CpControlIntent("resume", origin: encoded).perform()
                    let after = try store.snapshot()
                    check("Resume does not send a mutation", ledger.mutations == 0)
                    check("Resume retains spent snooze", after.run.armed && after.run.snoozeUsed)
                case "lost-response-pause":
                    transport.failMutation = true
                    ledger.effect("intent", fields: ["type": "CpJoinIntent", "action": "join with lost response"])
                    _ = try await CpJoinIntent(origin: encoded).perform()
                    let uncertain = try store.snapshot(); snapshot("admitted uncertain", uncertain)
                    ledger.effect("intent", fields: ["type": "CpControlIntent", "action": "pause"])
                    _ = try await CpControlIntent("pause", origin: try origin(uncertain)).perform()
                    let after = try store.snapshot()
                    check("Admitted failure sends one mutation", ledger.mutations == 1)
                    check("Local Pause preserves uncertain manual operation", !after.run.armed && after.operation?.stage == .uncertain && after.operation?.owner == uncertain.operation?.owner)
                case "snooze-pause":
                    ledger.effect("intent", fields: ["type": "CpSnoozeIntent", "action": "snooze"])
                    _ = try await CpSnoozeIntent(origin: encoded).perform()
                    let snoozed = try store.snapshot(); snapshot("snoozed", snoozed)
                    ledger.effect("intent", fields: ["type": "CpControlIntent", "action": "pause"])
                    _ = try await CpControlIntent("pause", origin: try origin(snoozed)).perform()
                    let after = try store.snapshot()
                    check("Snooze sends one standard hour mutation", ledger.mutations == 1 && ledger.snoozeSeconds == 3_600)
                    check("Pause retains spent snooze and turns mode off", !after.run.armed && after.run.snoozeUsed)
                case "retired-replaced":
                    transport.offer = "replacement-b"
                    _ = try await runtime.refresh(runAuto: false)
                    let fresh = try store.snapshot(); snapshot("fresh replacement", fresh)
                    let starts = ledger.count("start")
                    ledger.effect("intent", fields: ["type": "CpCommandIntent", "action": "accept retired origin"])
                    _ = try await CpCommandIntent("accept", origin: encoded).perform()
                    check("Retired origin starts no request", ledger.count("start") == starts)
                    transport.offer = "replacement-c"
                    ledger.effect("intent", fields: ["type": "CpCommandIntent", "action": "accept replaced preflight"])
                    _ = try await CpCommandIntent("accept", origin: try origin(fresh)).perform()
                    check("Replaced preflight sends no mutation", ledger.mutations == 0)
                    check("Replacement is reported", try store.snapshot().ownershipFeedback == .offerChanged)
                case "discarded-dependencies":
                    let bytes = try Data(contentsOf: directory.appendingPathComponent("cp-state.json"))
                    let starts = ledger.count("start"), prepares = ledger.count("prepare")
                    CpSessionStore.discardFixtureDependencies()
                    ledger.effect("intent", fields: ["type": "CpJoinIntent", "action": "discarded fixture join"])
                    _ = try await CpJoinIntent(origin: encoded).perform()
                    _ = try await CpControlIntent("join", origin: encoded).perform()
                    _ = try await WidgetRefreshIntent("com.rohit.hearth.chargepoint").perform()
                    _ = try await CpSetupIntent("signin").perform()
                    check("Discarded dependencies prepare/start nothing", ledger.count("start") == starts && ledger.count("prepare") == prepares)
                    check("Discarded dependencies have no reload/permission", ledger.count("reload") == 0 && ledger.count("permission") == 0)
                    check("Discarded dependency state bytes unchanged", try Data(contentsOf: directory.appendingPathComponent("cp-state.json")) == bytes)
                    do { _ = try CpSessionStore.repository(); check("No repository fallback", false) }
                    catch { check("No repository fallback", true) }
                default: break
                }
            }
            let after = try store.snapshot(); snapshot("after", after)
            display = try after.displaySnapshot()
            check("Store remains a private temporary UUID directory", directory.deletingLastPathComponent().resolvingSymlinksInPath() == FileManager.default.temporaryDirectory.resolvingSymlinksInPath())
            passed = checks.allSatisfy { $0["passed"] as? Bool == true }
            summary = "\(checks.filter { $0["passed"] as? Bool == true }.count)/\(checks.count) checks · \(ledger.mutations) mutations · \(ledger.count("permission")) permission requests"
        } catch {
            check("Fixture completed", false); summary = friendlyError(error); passed = false
        }
        running = false; finished = true
        // Publish UI semantics first; host screenshot capture waits for the settled private receipt.
        await Task.yield()
        await Task.yield()
        writeReceipt()
    }

    private func writeReceipt() {
        guard let directory else { return }
        let receipt: [String: Any] = ["case": caseName, "settled": true, "passed": passed,
            "scope": "in-process actual AppIntent.perform; visual production card reference, not WidgetKit",
            "cardWidthPt": 364, "cardHeightPt": 170, "privateDirectory": directory.path,
            "privateSuite": suiteName ?? "", "checks": checks, "snapshots": snapshots,
            "ledger": ledger.events, "summary": summary, "timestamp": Date.now.timeIntervalSince1970]
        do {
            let bytes = try JSONSerialization.data(withJSONObject: receipt, options: [.prettyPrinted, .sortedKeys])
            try bytes.write(to: directory.appendingPathComponent("result.json"), options: .atomic)
            // A fixed pointer inside this isolated app's temporary container lets simctl retrieve the result.
            try bytes.write(to: FileManager.default.temporaryDirectory.appendingPathComponent("cp-owned-native-result.json"), options: .atomic)
        } catch { summary = "Couldn't save native receipt" }
    }
}

private final class CpNativeLedger: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [[String: Any]] = []
    private var snooze = 0
    func effect(_ kind: String, fields: [String: Any] = [:]) {
        lock.withLock {
            var item = fields; item["kind"] = kind; item["sequence"] = values.count + 1
            item["timestamp"] = Date.now.timeIntervalSince1970; values.append(item)
        }
    }
    func count(_ kind: String) -> Int { lock.withLock { values.filter { $0["kind"] as? String == kind }.count } }
    var mutations: Int { lock.withLock { values.filter { $0["kind"] as? String == "start" && $0["mutation"] as? Bool == true }.count } }
    var events: [[String: Any]] { lock.withLock { values } }
    var snoozeSeconds: Int { lock.withLock { snooze } }
    func recordSnooze(_ seconds: Int) { lock.withLock { snooze = seconds } }
    static func state(_ value: CpStoreSnapshot) -> [String: Any] {
        var result: [String: Any] = ["armed": value.run.armed, "snoozeUsed": value.run.snoozeUsed,
            "drivePushed": value.run.drivePushed, "startedAt": value.run.startedAt,
            "accountGeneration": value.context.accountGeneration, "selectionRevision": value.context.selectionRevision,
            "runID": value.context.runID, "modeRevision": value.context.modeRevision,
            "accountID": value.session.userId, "expired": value.session.expired, "joinExpired": value.session.joinExpired]
        if let reading = value.reading { result["observedAt"] = reading.observedAt.timeIntervalSince1970 }
        if let operation = value.operation {
            result["operationID"] = operation.owner.operationID; result["operationStage"] = operation.stage.rawValue
            result["operationCause"] = operation.owner.cause.rawValue
            result["mutationAdmissionID"] = operation.mutationAdmissionID
        }
        result["feedback"] = value.ownershipFeedback?.rawValue
        result["observationID"] = value.renderedOrigin?.observationID
        result["actionRevision"] = value.renderedOrigin?.actionRevision
        return result
    }
}

private final class CpNativeTransport: CpOwnedTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var currentPhase = "NOT_QUEUED"
    private var currentOffer = "native-offer-a"
    private var fail = false
    private let startedAt = Int64(Date.now.timeIntervalSince1970) - 120
    private let ledger: CpNativeLedger
    private let stationNames: [Int64: String]
    init(ledger: CpNativeLedger, stationNames: [Int64: String] = [:]) {
        self.ledger = ledger; self.stationNames = stationNames
    }
    var phase: String { get { lock.withLock { currentPhase } } set { lock.withLock { currentPhase = newValue } } }
    var offer: String { get { lock.withLock { currentOffer } } set { lock.withLock { currentOffer = newValue } } }
    var failMutation: Bool { get { lock.withLock { fail } } set { lock.withLock { fail = newValue } } }
    func prepare(_ request: URLRequest) throws -> any CpPreparedRequest {
        guard let url = request.url else { throw CpObservationError.malformed }
        let path = url.path
        let object = request.httpBody.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
        let mutation = path.hasSuffix("/join") || path.hasSuffix("/snoozeV2") || path.hasSuffix("/acceptV2")
        let body: String
        if mutation { body = "{\"result\":true,\"response\":{\"success\":true}}" }
        else if object?["user_status"] != nil { body = try status() }
        else if object?["map_data"] != nil { body = "{\"map_data\":{\"stations\":[]}}" }
        else if path.hasSuffix("/inlinestatus") { body = "{\"positionInline\":3}" }
        else if path.contains("/get_notification_detail/") { body = "{\"response\":{\"remainingSnoozeCount\":1}}" }
        else { throw CpObservationError.malformed }
        ledger.effect("prepare", fields: ["path": path, "mutation": mutation])
        let fails = mutation && failMutation
        if path.hasSuffix("/snoozeV2"), let form = request.httpBody.flatMap({ String(data: $0, encoding: .utf8) }),
           let seconds = Int(form.replacingOccurrences(of: "snoozeTime=", with: "")) { ledger.recordSnooze(seconds) }
        return CpNativePrepared(url: url, body: body, fail: fails, ledger: ledger, mutation: mutation) { [self] in
            if mutation && !fails {
                if path.hasSuffix("/join") { phase = "WAITING" }
                if path.hasSuffix("/snoozeV2") { phase = "PASS" }
            }
        }
    }
    private func status() throws -> String {
        let phase = self.phase, offer = self.offer
        var state: [String: Any] = ["state": phase]
        if ["ACCEPT_PENDING", "PENDING_PLUG_IN", "PASS"].contains(phase) {
            state.merge(["token": offer, "deviceId": 1, "portNo": 1,
                "startTimeUTC": startedAt,
                "duration": phase == "PASS" ? 3_600 : 1_800]) { _, newer in newer }
        }
        let stations: [[String: Any]] = phase == "NOT_QUEUED" ? [] : [Int64(1), 2].map { id in
            var station: [String: Any] = ["deviceId": id]
            if let name = stationNames[id] { station["name"] = name }
            return station
        }
        return String(decoding: try JSONSerialization.data(withJSONObject: ["user_status": ["waitlist": [
            "state": state, "stations": stations]]]), as: UTF8.self)
    }
}

private struct CpNativePrepared: CpPreparedRequest {
    let url: URL
    let body: String
    let fail: Bool
    let ledger: CpNativeLedger
    let mutation: Bool
    let onStart: @Sendable () -> Void
    func start() {
        ledger.effect("start", fields: ["path": url.path, "mutation": mutation]); onStart()
    }
    func cancel() { ledger.effect("cancel", fields: ["path": url.path]) }
    func response() async throws -> (Data, HTTPURLResponse) {
        if fail { ledger.effect("lostResponse", fields: ["path": url.path]); throw URLError(.networkConnectionLost) }
        ledger.effect("response", fields: ["path": url.path, "status": 200])
        return (Data(body.utf8), HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!)
    }
}
#endif
