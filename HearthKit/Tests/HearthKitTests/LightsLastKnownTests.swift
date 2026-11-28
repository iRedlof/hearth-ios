import Testing
import Foundation
@testable import HearthKit

@Suite("Lights keep what was last known when Home Assistant can't be reached")
struct LightsLastKnownTests {
    private let now = Date(timeIntervalSince1970: 1_793_379_600)
    private let unreachable = "Can't reach Home Assistant"
    private let config = HaConfig(baseUrl: "https://home.example", token: "inert", entityId: "")
    private let reading = """
    [{"entity_id":"light.kitchen","name":"Kitchen","state":"on","brightness":204,"group":false},
     {"entity_id":"light.desk","name":"Desk lamp","state":"on","brightness":128,"group":false},
     {"entity_id":"light.porch","name":"Porch","state":"off","group":false}]
    """

    private func ready(_ config: HaConfig? = nil) -> LightsSnapshot {
        mapLightsSnapshot(config ?? self.config, reply: .success(reading), now: now.addingTimeInterval(-7_200))
    }
    private func names(_ snapshot: LightsSnapshot) -> [String] {
        (snapshot.summary.on + snapshot.summary.pinned + snapshot.summary.off).map(\.name)
    }

    @Test("A failed read keeps every last-known light, by name, none of them reporting")
    func keepsLastKnown() {
        let failed = mapLightsSnapshot(config, reply: .failure(HaError(unreachable)), previous: ready(), now: now)
        #expect(failed.state == .failed)
        #expect(failed.error == unreachable)
        #expect(names(failed) == ["Desk lamp", "Kitchen", "Porch"])
        let all = failed.summary.on + failed.summary.pinned + failed.summary.off
        #expect(all.allSatisfy { !$0.available && !$0.on && $0.percent == nil && $0.tile == "Unavailable" })
        #expect(failed.summary.onCount == 0)
        #expect(failed.summary.offCount == 0)
    }

    @Test("Nothing in a failed snapshot can be read as a fresh check")
    func noFreshStamp() {
        let failed = mapLightsSnapshot(config, reply: .failure(HaError(unreachable)), previous: ready(), now: now)
        #expect(failed.checkedAt.isEmpty)
    }

    @Test("A malformed reply is a failure too, and also keeps the last-known lights")
    func malformedKeepsLastKnown() {
        let failed = mapLightsSnapshot(config, reply: .success("{\"error\":\"bad template\"}"), previous: ready(), now: now)
        #expect(failed.state == .failed)
        #expect(names(failed).count == 3)
    }

    @Test("Pinned lights stay in the always-shown section")
    func pinsSurvive() {
        var pinned = config
        pinned.lightPinsJson = "[\"light.porch\"]"
        let failed = mapLightsSnapshot(pinned, reply: .failure(HaError(unreachable)), previous: ready(pinned), now: now)
        #expect(failed.summary.pinned.map(\.id) == ["light.porch"])
        #expect(failed.summary.on.map(\.id) == ["light.desk", "light.kitchen"])
    }

    @Test("Repeated failures keep the same last-known lights")
    func failuresChain() {
        let first = mapLightsSnapshot(config, reply: .failure(HaError(unreachable)), previous: ready(), now: now)
        let second = mapLightsSnapshot(config, reply: .failure(HaError(unreachable)), previous: first,
                                       now: now.addingTimeInterval(900))
        #expect(names(second) == names(first))
        #expect(second.state == .failed)
    }

    @Test("With nothing last known a failed read has no lights")
    func nothingKnown() {
        let failed = mapLightsSnapshot(config, reply: .failure(HaError(unreachable)), now: now)
        #expect(failed.state == .failed)
        #expect(names(failed).isEmpty)
        let fromLoading = mapLightsSnapshot(config, reply: .failure(HaError(unreachable)), previous: .loading, now: now)
        #expect(names(fromLoading).isEmpty)
    }

    @Test("A successful read replaces what was last known")
    func successReplaces() {
        let failed = mapLightsSnapshot(config, reply: .failure(HaError(unreachable)), previous: ready(), now: now)
        let fresh = mapLightsSnapshot(config, reply: .success("[{\"entity_id\":\"light.hall\",\"name\":\"Hall\",\"state\":\"on\",\"group\":false}]"),
                                      previous: failed, now: now)
        #expect(fresh.state == .ready)
        #expect(names(fresh) == ["Hall"])
        #expect(!fresh.checkedAt.isEmpty)
    }

    @Test("Not set up shows no last-known lights")
    func setupIgnoresPrevious() {
        let setup = mapLightsSnapshot(nil, reply: .failure(HaError(unreachable)), previous: ready(), now: now)
        #expect(setup.state == .setup)
        #expect(names(setup).isEmpty)
    }

    @Test("The fetch hands its previous snapshot to a failed read")
    func fetchKeepsPrevious() async {
        let previous = ready()
        let failed = await fetchLightsSnapshot(config, now: now, previous: previous, read: { throw URLError(.timedOut) })
        #expect(failed.state == .failed)
        #expect(names(failed) == ["Desk lamp", "Kitchen", "Porch"])
    }

    @Test("Only a well-formed lights reading may be saved as last known")
    func validation() throws {
        try validateLightsReading(reading)
        try validateLightsReading("[]")
        #expect(throws: HaError.self) { try validateLightsReading("{\"error\":\"bad template\"}") }
        #expect(throws: HaError.self) { try validateLightsReading("[{\"entity_id\":\"light.x\",\"state\":\"bogus\"}]") }
        #expect(throws: HaError.self) { try validateLightsReading("[{\"entity_id\":\"switch.x\",\"state\":\"on\"}]") }
    }
}

@Suite("Lights last-known cache in the shared store")
struct LightsCollectionStoreTests {
    private let config = HaConfig(baseUrl: "https://home.example", token: "account-A", entityId: "alarm_control_panel.home")
    private let reading = #"[{"entity_id":"light.kitchen","name":"Kitchen","state":"on","group":false}]"#

    private func withStore(_ body: (HaStateStore) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try body(HaStateStore(directory: directory, initialConfig: config, initialScope: "scope-A"))
    }

    @Test("A failed read keeps the last successful lights reading and when it was observed")
    func failureKeepsPayload() throws {
        try withStore { store in
            let start = try store.snapshot()
            let first = try #require(try store.beginCollectionRead("lights", expectedScope: start.scope,
                                                                   expectedRevision: start.collectionRevision))
            _ = try store.mergeCollection("lights", reply: .success(reading), expectedScope: start.scope,
                expectedRevision: start.collectionRevision, readID: first, now: Date(timeIntervalSince1970: 100))
            let next = try #require(try store.beginCollectionRead("lights", expectedScope: start.scope,
                                                                  expectedRevision: start.collectionRevision))
            let result = try #require(try store.mergeCollection("lights", reply: .failure(HaError("Can't reach Home Assistant")),
                expectedScope: start.scope, expectedRevision: start.collectionRevision, readID: next,
                now: Date(timeIntervalSince1970: 200)))
            let cache = try #require(result.collectionCaches["lights"])
            #expect(cache.payload == reading)
            #expect(cache.observedAt == Date(timeIntervalSince1970: 100))
            #expect(cache.error == "Can't reach Home Assistant")
        }
    }

    @Test("Another account never sees the previous account's lights")
    func accountChangeDropsCache() throws {
        try withStore { store in
            let start = try store.snapshot()
            let read = try #require(try store.beginCollectionRead("lights", expectedScope: start.scope,
                                                                  expectedRevision: start.collectionRevision))
            _ = try store.mergeCollection("lights", reply: .success(reading), expectedScope: start.scope,
                expectedRevision: start.collectionRevision, readID: read, now: Date(timeIntervalSince1970: 100))
            let other = HaConfig(baseUrl: "https://other.example", token: "account-B", entityId: "alarm_control_panel.home")
            let changed = try store.saveConfig(other)
            #expect(changed.collectionCaches["lights"] == nil)
            #expect(try store.beginCollectionRead("lights", expectedScope: start.scope,
                                                  expectedRevision: start.collectionRevision) == nil)
        }
    }
}
