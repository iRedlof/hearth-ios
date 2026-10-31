import Foundation
import XCTest
@testable import HearthKit
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

private final class CpStoreClaimResults: @unchecked Sendable {
    private let lock = NSLock()
    private var accepted = 0
    private var errors: [String] = []
    func record(_ result: CpStoreSnapshot?) {
        lock.lock(); defer { lock.unlock() }
        if result != nil { accepted += 1 }
    }
    func record(_ error: Error) {
        lock.lock(); defer { lock.unlock() }
        errors.append(String(describing: error))
    }
    var values: (accepted: Int, errors: [String]) {
        lock.lock(); defer { lock.unlock() }
        return (accepted, errors)
    }
}

final class CpStateStoreProcessTests: XCTestCase {
    func testIndependentConcurrentHandlesConsumeOneExpectedSettingsRevision() throws {
        let directory = try CpStoreFixture.directory(self)
        let store = CpStateStore(directory: directory)
        let before = try store.bootstrap(legacy: CpStoreFixture.legacy, now: CpStoreFixture.now)
        let results = CpStoreClaimResults()
        DispatchQueue.concurrentPerform(iterations: 64) { _ in
            do {
                results.record(try CpStateStore(directory: directory)
                    .edit(expected: before.settingsOrigin, edit: .alert(.offer, true), now: CpStoreFixture.now))
            } catch { results.record(error) }
        }
        XCTAssertEqual(results.values.accepted, 1)
        XCTAssertTrue(results.values.errors.isEmpty, "\(results.values.errors)")
        XCTAssertTrue(try store.snapshot(now: CpStoreFixture.now).alerts.offer)
        XCTAssertNotEqual(try store.snapshot(now: CpStoreFixture.now).context.settingsRevision,
                          before.context.settingsRevision)
    }

    #if os(macOS)
    /// Launch the package's selected XCTest in a separate process, not through MainActor.
    func testAnotherProcessWaitsForThePermanentStateSidecarBeforeEditing() throws {
        let directory = try CpStoreFixture.directory(self)
        let store = CpStateStore(directory: directory)
        let before = try store.bootstrap(legacy: CpStoreFixture.legacy, now: CpStoreFixture.now)
        try JSONEncoder().encode(before.settingsOrigin)
            .write(to: directory.appendingPathComponent("test-origin.json"))
        let descriptor = open(directory.appendingPathComponent("cp-state.lock").path, O_RDWR)
        XCTAssertGreaterThanOrEqual(descriptor, 0)
        guard descriptor >= 0 else { return }
        var held = false
        defer {
            if held { _ = flock(descriptor, LOCK_UN) }
            close(descriptor)
        }
        XCTAssertEqual(flock(descriptor, LOCK_EX), 0)
        held = true
        let process = Process()
        let executable = URL(fileURLWithPath: CommandLine.arguments[0])
        let selector = "HearthKitTests.CpStateStoreProcessTests/testChildEntry"
        process.executableURL = executable
        if executable.lastPathComponent == "xctest" {
            process.arguments = ["-XCTest", selector, Bundle(for: CpStateStoreProcessTests.self).bundleURL.path]
        } else {
            process.arguments = [selector]
        }
        let childTemporaryDirectory = directory.appendingPathComponent("test-child-tmp", isDirectory: true)
        try FileManager.default.createDirectory(at: childTemporaryDirectory, withIntermediateDirectories: true)
        // A runner can print its environment on usage failure; never inherit host credentials.
        process.environment = [
            "HEARTH_CP_STATE_CHILD_DIRECTORY": directory.path,
            "PATH": "/usr/bin:/bin:/usr/sbin:/sbin",
            "TMPDIR": childTemporaryDirectory.path + "/"
        ]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = output
        try process.run()
        defer { if process.isRunning { process.terminate() } }
        let ready = directory.appendingPathComponent("test-child-ready")
        let complete = directory.appendingPathComponent("test-child-complete")
        let readyDeadline = Date().addingTimeInterval(5)
        while !FileManager.default.fileExists(atPath: ready.path), process.isRunning, Date() < readyDeadline {
            Thread.sleep(forTimeInterval: 0.005)
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: ready.path), "Child must observe the held sidecar")
        Thread.sleep(forTimeInterval: 0.1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: complete.path),
                       "A different process must not edit while the parent holds cp-state.lock")
        _ = flock(descriptor, LOCK_UN)
        held = false
        let completionDeadline = Date().addingTimeInterval(5)
        while process.isRunning, Date() < completionDeadline { Thread.sleep(forTimeInterval: 0.005) }
        if process.isRunning { process.terminate() }
        process.waitUntilExit()
        let text = String(data: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        XCTAssertEqual(process.terminationStatus, 0, text)
        XCTAssertEqual(try String(contentsOf: complete, encoding: .utf8), "accepted")
        XCTAssertTrue(try store.snapshot(now: CpStoreFixture.now).alerts.offer)
    }

    /// Ordinary test enumeration does nothing; the parent supplies a private role directory.
    func testChildEntry() throws {
        guard let path = ProcessInfo.processInfo.environment["HEARTH_CP_STATE_CHILD_DIRECTORY"] else { return }
        let directory = URL(fileURLWithPath: path)
        let origin = try JSONDecoder().decode(CpSettingsOrigin.self,
            from: Data(contentsOf: directory.appendingPathComponent("test-origin.json")))
        let descriptor = open(directory.appendingPathComponent("cp-state.lock").path, O_RDWR)
        XCTAssertGreaterThanOrEqual(descriptor, 0)
        guard descriptor >= 0 else { return }
        defer { close(descriptor) }
        let probe = flock(descriptor, LOCK_EX | LOCK_NB)
        XCTAssertEqual(probe, -1, "The parent must hold the exact permanent inode")
        XCTAssertTrue(errno == EWOULDBLOCK || errno == EAGAIN)
        if probe == 0 { _ = flock(descriptor, LOCK_UN) }
        try Data("held".utf8).write(to: directory.appendingPathComponent("test-child-ready"))
        let result = try CpStateStore(directory: directory)
            .edit(expected: origin, edit: .alert(.offer, true), now: CpStoreFixture.now)
        XCTAssertNotNil(result)
        try Data((result == nil ? "rejected" : "accepted").utf8)
            .write(to: directory.appendingPathComponent("test-child-complete"))
    }
    #endif
}
