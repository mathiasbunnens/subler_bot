import XCTest
@testable import AutomationCore

final class FolderWatcherTests: XCTestCase {
    func testRealWritableDescriptorBlocksReadinessWithoutTouchingMedia() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("fixture.mkv")
        try Data("synthetic".utf8).write(to: source)
        let fingerprint = try FileIdentity.fingerprint(source)
        func lsof() throws -> (String, Int32) {
            let process = Process(); process.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
            process.arguments = ["-F", "a", "--", source.path]
            let pipe = Pipe(); process.standardOutput = pipe; process.standardError = FileHandle.nullDevice
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile(); process.waitUntilExit()
            return (String(decoding: data, as: UTF8.self), process.terminationStatus)
        }
        let handle = try FileHandle(forWritingTo: source)
        defer { try? handle.close() }
        let writable = try lsof()
        XCTAssertFalse(FileReadinessPolicy.isSafe(before: fingerprint, after: fingerprint, lsofOutput: writable.0, exitStatus: writable.1))
        try handle.close()
        let closed = try lsof()
        XCTAssertTrue(FileReadinessPolicy.isSafe(before: fingerprint, after: try FileIdentity.fingerprint(source), lsofOutput: closed.0, exitStatus: closed.1))
        XCTAssertEqual(try Data(contentsOf: source), Data("synthetic".utf8))
    }
    func testWritableDescriptorAndMutationRejectReadiness() {
        XCTAssertFalse(FileReadinessPolicy.isSafe(before: "a", after: "a", lsofOutput: "p123\nf4\naw\n", exitStatus: 0))
        XCTAssertFalse(FileReadinessPolicy.isSafe(before: "a", after: "a", lsofOutput: "au\n", exitStatus: 0))
        XCTAssertFalse(FileReadinessPolicy.isSafe(before: "a", after: "changed", lsofOutput: "", exitStatus: 1))
        XCTAssertFalse(FileReadinessPolicy.isSafe(before: "a", after: nil, lsofOutput: "", exitStatus: 1))
        XCTAssertFalse(FileReadinessPolicy.isSafe(before: "a", after: "a", lsofOutput: "", exitStatus: 2))
        XCTAssertTrue(FileReadinessPolicy.isSafe(before: "a", after: "a", lsofOutput: "ar\n", exitStatus: 0))
        XCTAssertTrue(FileReadinessPolicy.isSafe(before: "a", after: "a", lsofOutput: "", exitStatus: 1))
    }
    func testResetAndZeroSizeRestartObservation() {
        var tracker = FileStabilityTracker()
        let time = Date(timeIntervalSince1970: 1000)
        _ = tracker.observe(path: "file", size: 100, modified: time, now: time)
        tracker.reset(path: "file")
        XCTAssertFalse(tracker.observe(path: "file", size: 100, modified: time, now: time.addingTimeInterval(10)))
        XCTAssertTrue(tracker.observe(path: "file", size: 100, modified: time, now: time.addingTimeInterval(20)))
        XCTAssertFalse(tracker.observe(path: "file", size: 0, modified: time, now: time.addingTimeInterval(21)))
        XCTAssertFalse(tracker.observe(path: "file", size: 100, modified: time, now: time.addingTimeInterval(22)))
    }
    func testModificationDateChangeRestartsTenSecondsEvenWithSameSize() {
        var tracker = FileStabilityTracker()
        let time = Date(timeIntervalSince1970: 1000)
        _ = tracker.observe(path: "file", size: 100, modified: time, now: time)
        XCTAssertFalse(tracker.observe(path: "file", size: 100, modified: time.addingTimeInterval(5), now: time.addingTimeInterval(10)))
        XCTAssertFalse(tracker.observe(path: "file", size: 100, modified: time.addingTimeInterval(5), now: time.addingTimeInterval(19)))
        XCTAssertTrue(tracker.observe(path: "file", size: 100, modified: time.addingTimeInterval(5), now: time.addingTimeInterval(20)))
    }
    func testRequiresTenSecondQuietPeriodAndRestartsOnSizeChange() {
        var tracker = FileStabilityTracker()
        let time = Date(timeIntervalSince1970: 1000)
        XCTAssertFalse(tracker.observe(path: "test.mkv", size: 100, modified: time, now: time))
        XCTAssertFalse(tracker.observe(path: "test.mkv", size: 100, modified: time, now: time.addingTimeInterval(9)))
        XCTAssertTrue(tracker.observe(path: "test.mkv", size: 100, modified: time, now: time.addingTimeInterval(10)))
        XCTAssertFalse(tracker.observe(path: "test.mkv", size: 200, modified: time.addingTimeInterval(11), now: time.addingTimeInterval(11)))
        XCTAssertFalse(tracker.observe(path: "test.mkv", size: 200, modified: time.addingTimeInterval(11), now: time.addingTimeInterval(20)))
        XCTAssertTrue(tracker.observe(path: "test.mkv", size: 200, modified: time.addingTimeInterval(11), now: time.addingTimeInterval(21)))
    }
}
