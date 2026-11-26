import XCTest
@testable import HearthKit

@MainActor
final class SettingsDiscoveryTests: XCTestCase {
    private let config = HaConfig(baseUrl: "https://fixture.invalid", token: "fixture", entityId: "")

    private func store() throws -> HaStateStore {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return HaStateStore(directory: directory, initialConfig: config, initialScope: "account-a")
    }

    func testAccountChangedBeforeDiscoveryDoesNotRead() async throws {
        let store = try store()
        let captured = try store.snapshot()
        _ = try store.replaceConfig(config)
        var reads = 0
        do {
            _ = try await settingsDiscoveryJson(config: config, scope: captured.scope,
                current: { try? store.snapshot() }, read: { _ in reads += 1; return "[]" })
            XCTFail("An old screen must not discover for a replacement account")
        } catch { }
        XCTAssertEqual(reads, 0)
    }

    func testDelayedAccountAResultIsRejectedAfterAccountB() async throws {
        let store = try store()
        let captured = try store.snapshot()
        do {
            _ = try await settingsDiscoveryJson(config: config, scope: captured.scope,
                current: { try? store.snapshot() }, read: { _ in
                    var other = self.config
                    other.baseUrl = "https://other.invalid"
                    _ = try store.saveConfig(other)
                    return #"[{"entity_id":"lock.account_a","state":"locked"}]"#
                })
            XCTFail("Account A discovery must not publish into B")
        } catch { }
        XCTAssertEqual(try store.snapshot().config?.baseUrl, "https://other.invalid")
    }

    func testMissingScopeAndAuthDoNotStartTransport() async throws {
        let store = try store()
        let captured = try store.snapshot()
        for scope in [nil, captured.scope] {
            var requested = config
            if scope != nil { requested.token = "" }
            var reads = 0
            do {
                _ = try await settingsDiscoveryJson(config: requested, scope: scope,
                    current: { try? store.snapshot() }, read: { _ in reads += 1; return "[]" })
                XCTFail("Unowned or unauthenticated settings cannot discover")
            } catch { }
            XCTAssertEqual(reads, 0)
        }
    }

    func testTokenAuthAndSameScopeEntityEditRemainUsable() async throws {
        let store = try store()
        let captured = try store.snapshot()
        var latest = config
        latest.climateId = "climate.new"
        _ = try store.saveConfig(latest)
        let json = try await settingsDiscoveryJson(config: config, scope: captured.scope,
            current: { try? store.snapshot() }, read: { supplied in
                XCTAssertEqual(supplied.climateId, "climate.new")
                XCTAssertTrue(supplied.hasAuth)
                return "[]"
            })
        XCTAssertEqual(json, "[]")
    }

    func testFailurePreservesSavedChoices() async throws {
        let store = try store()
        var selected = config
        selected.doorIdsJson = #"["lock.missing"]"#
        selected.doorsChosen = true
        let captured = try store.saveConfig(selected)
        do {
            _ = try await settingsDiscoveryJson(config: selected, scope: captured.scope,
                current: { try? store.snapshot() }, read: { _ in throw HaError("Offline") })
            XCTFail("Transport errors must propagate")
        } catch {
            XCTAssertEqual(friendlyError(error), "Offline")
        }
        XCTAssertEqual(try store.snapshot().config?.doorIds, ["lock.missing"])
        XCTAssertTrue(try store.snapshot().config?.doorsChosen == true)
    }

    func testCancellationPropagates() async throws {
        let store = try store()
        let captured = try store.snapshot()
        do {
            _ = try await settingsDiscoveryJson(config: config, scope: captured.scope,
                current: { try? store.snapshot() }, read: { _ in throw CancellationError() })
            XCTFail("Cancellation must not turn into an empty discovery")
        } catch {
            XCTAssertTrue(error is CancellationError)
        }
    }

    func testCancelledURLTransportRemainsCancellation() async throws {
        let store = try store()
        let captured = try store.snapshot()
        do {
            _ = try await settingsDiscoveryJson(config: config, scope: captured.scope,
                current: { try? store.snapshot() }, read: { _ in throw URLError(.cancelled) })
            XCTFail("Cancelled URL transport cannot become a picker failure")
        } catch {
            XCTAssertTrue(error is CancellationError)
        }
    }
}
