import XCTest
@testable import HearthKit

final class HaAuthTests: XCTestCase {
    private func config(_ server: String = "https://home.invalid", refresh: String = "inert-refresh") -> HaConfig {
        HaConfig(baseUrl: server, token: "", entityId: "", refreshToken: refresh)
    }

    func testSameRefreshTokenOnAnotherServerRenewsItsOwnBearer() async throws {
        let renewals = AuthRenewals()
        let auth = HaAuth(renew: { try await renewals.renew($0, $1) }, nowMilliseconds: { 100_000 })
        let first = try await auth.accessToken(config("https://first.invalid"))
        let second = try await auth.accessToken(config("https://second.invalid"))
        XCTAssertEqual(first, "access-1")
        XCTAssertEqual(second, "access-2")
        let calls = await renewals.calls()
        XCTAssertEqual(calls.map(\.server), ["https://first.invalid", "https://second.invalid"])
    }

    func testTrailingSlashVariationsReuseTheSameServerCache() async throws {
        let renewals = AuthRenewals()
        let auth = HaAuth(renew: { try await renewals.renew($0, $1) }, nowMilliseconds: { 100_000 })
        let first = try await auth.accessToken(config("https://home.invalid/"))
        let second = try await auth.accessToken(config("https://home.invalid///"))
        XCTAssertEqual(first, second)
        let calls = await renewals.calls()
        XCTAssertEqual(calls.count, 1)
    }

    func testMeaningfulServerPathChangeDoesNotReuseTheBearer() async throws {
        let renewals = AuthRenewals()
        let auth = HaAuth(renew: { try await renewals.renew($0, $1) }, nowMilliseconds: { 100_000 })
        let first = try await auth.accessToken(config("https://home.invalid/one/"))
        let second = try await auth.accessToken(config("https://home.invalid/two"))
        XCTAssertNotEqual(first, second)
        let calls = await renewals.calls()
        XCTAssertEqual(calls.count, 2)
    }

    func testDifferentRefreshCredentialOnTheSameServerRenews() async throws {
        let renewals = AuthRenewals()
        let auth = HaAuth(renew: { try await renewals.renew($0, $1) }, nowMilliseconds: { 100_000 })
        let first = try await auth.accessToken(config(refresh: "inert-account-a"))
        let second = try await auth.accessToken(config(refresh: "inert-account-b"))
        XCTAssertNotEqual(first, second)
        let calls = await renewals.calls()
        XCTAssertEqual(calls.map(\.refresh), ["inert-account-a", "inert-account-b"])
    }

    func testFreshCacheRenewsAtTheExactSixtySecondBoundary() async throws {
        let clock = AuthClock(100_000)
        let renewals = AuthRenewals(expiresAt: 300_000)
        let auth = HaAuth(renew: { try await renewals.renew($0, $1) }, nowMilliseconds: { clock.now() })
        let first = try await auth.accessToken(config())
        clock.set(239_999)
        let fresh = try await auth.accessToken(config())
        XCTAssertEqual(first, fresh)
        clock.set(240_000)
        let boundary = try await auth.accessToken(config())
        XCTAssertNotEqual(first, boundary)
        let calls = await renewals.calls()
        XCTAssertEqual(calls.count, 2)
    }

    func testExpiredCacheRenewsInsteadOfReturningTheOldBearer() async throws {
        let clock = AuthClock(100_000)
        let renewals = AuthRenewals(expiresAt: 300_000)
        let auth = HaAuth(renew: { try await renewals.renew($0, $1) }, nowMilliseconds: { clock.now() })
        let first = try await auth.accessToken(config())
        clock.set(300_001)
        let expired = try await auth.accessToken(config())
        XCTAssertNotEqual(first, expired)
        let calls = await renewals.calls()
        XCTAssertEqual(calls.count, 2)
    }

    func testRenewalFailureDoesNotBecomeACachedSuccess() async throws {
        let renewals = AuthRenewals(failures: 1)
        let auth = HaAuth(renew: { try await renewals.renew($0, $1) }, nowMilliseconds: { 100_000 })
        do {
            _ = try await auth.accessToken(config())
            XCTFail("A failed renewal must propagate")
        } catch let error as HaError {
            XCTAssertEqual(error.message, "Fixture renewal failed")
        }
        let recovered = try await auth.accessToken(config())
        let cached = try await auth.accessToken(config())
        XCTAssertEqual(recovered, cached)
        let calls = await renewals.calls()
        XCTAssertEqual(calls.count, 2)
    }

    func testForgetClearsAnAlreadyCompletedRenewal() async throws {
        let renewals = AuthRenewals()
        let auth = HaAuth(renew: { try await renewals.renew($0, $1) }, nowMilliseconds: { 100_000 })
        let first = try await auth.accessToken(config())
        await auth.forget()
        let next = try await auth.accessToken(config())
        XCTAssertNotEqual(first, next)
        let calls = await renewals.calls()
        XCTAssertEqual(calls.count, 2)
    }

    func testForgetRejectsAPausedRenewalAndPreservesTheNewCache() async throws {
        let started = AuthSignal(), resume = AuthSignal(), renewals = AuthRenewals()
        let auth = HaAuth(renew: { server, refresh in
            let tokens = try await renewals.renew(server, refresh)
            if refresh == "inert-old" {
                await started.signal()
                await resume.wait()
            }
            return tokens
        }, nowMilliseconds: { 100_000 })
        let oldConfig = config(refresh: "inert-old")
        let newConfig = config(refresh: "inert-new")
        let old = Task { try await auth.accessToken(oldConfig) }
        await started.wait()
        await auth.forget()
        let current = try await auth.accessToken(newConfig)
        await resume.signal()
        do {
            _ = try await old.value
            XCTFail("Forget must revoke an earlier suspended renewal")
        } catch let error as HaError {
            XCTAssertEqual(error.message, "Configuration changed · Refresh to check")
        }
        let next = try await auth.accessToken(newConfig)
        XCTAssertEqual(current, next)
        let calls = await renewals.calls()
        XCTAssertEqual(calls.count, 2)
    }

    func testOlderServerReplyReturnsItsOwnBearerWithoutReplacingTheNewerCache() async throws {
        let started = AuthSignal(), resume = AuthSignal(), renewals = AuthRenewals()
        let auth = HaAuth(renew: { server, refresh in
            let tokens = try await renewals.renew(server, refresh)
            if server == "https://older.invalid" {
                await started.signal()
                await resume.wait()
            }
            return tokens
        }, nowMilliseconds: { 100_000 })
        let olderConfig = config("https://older.invalid")
        let newerConfig = config("https://newer.invalid")
        let older = Task { try await auth.accessToken(olderConfig) }
        await started.wait()
        let newer = try await auth.accessToken(newerConfig)
        await resume.signal()
        let olderBearer = try await older.value
        XCTAssertEqual(olderBearer, "access-1")
        XCTAssertEqual(newer, "access-2")
        let cached = try await auth.accessToken(newerConfig)
        XCTAssertEqual(cached, newer)
        let calls = await renewals.calls()
        XCTAssertEqual(calls.count, 2)
    }

    func testCancellationDuringRenewalPreventsTokenPublicationAndCaching() async throws {
        let started = AuthSignal(), resume = AuthSignal(), renewals = AuthRenewals()
        let auth = HaAuth(renew: { server, refresh in
            let tokens = try await renewals.renew(server, refresh)
            await started.signal()
            await resume.wait()
            return tokens
        }, nowMilliseconds: { 100_000 })
        let requested = config()
        let cancelled = Task { try await auth.accessToken(requested) }
        await started.wait()
        cancelled.cancel()
        await resume.signal()
        do {
            _ = try await cancelled.value
            XCTFail("A cancelled renewal must not publish a bearer")
        } catch is CancellationError {}
        let next = try await auth.accessToken(requested)
        XCTAssertEqual(next, "access-2")
        let calls = await renewals.calls()
        XCTAssertEqual(calls.count, 2)
    }
}

private actor AuthRenewals {
    struct Call: Sendable {
        let server: String
        let refresh: String
    }
    private var recorded: [Call] = []
    private let expiresAt: Double
    private var failures: Int

    init(expiresAt: Double = 1_000_000, failures: Int = 0) {
        self.expiresAt = expiresAt
        self.failures = failures
    }

    func renew(_ server: String, _ refresh: String) throws -> HaTokens {
        recorded.append(Call(server: server, refresh: refresh))
        if failures > 0 {
            failures -= 1
            throw HaError("Fixture renewal failed")
        }
        return HaTokens(access: "access-\(recorded.count)", expiresAt: expiresAt, refresh: nil)
    }

    func calls() -> [Call] { recorded }
}

private actor AuthSignal {
    private var signaled = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func signal() {
        signaled = true
        for waiter in waiters { waiter.resume() }
        waiters = []
    }

    func wait() async {
        if signaled { return }
        await withCheckedContinuation { waiters.append($0) }
    }
}

private final class AuthClock: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Double

    init(_ value: Double) { self.value = value }
    func now() -> Double {
        lock.lock()
        defer { lock.unlock() }
        return value
    }
    func set(_ value: Double) {
        lock.lock()
        defer { lock.unlock() }
        self.value = value
    }
}
