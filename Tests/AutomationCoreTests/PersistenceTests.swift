import XCTest
@testable import AutomationCore

final class PersistenceTests: XCTestCase {
    func testInterruptedConversionNeverCompletes() {
        var job = MovieJob(sourcePath: "/test.mkv", fingerprint: "test")
        job.status = .converting
        job.recover()
        XCTAssertEqual(job.status, .pending)
        XCTAssertFalse(job.validated)
    }
    func testInterruptedValidatedTransferWaits() {
        var job = MovieJob(sourcePath: "/test.mkv", fingerprint: "test")
        job.status = .transferring; job.validated = true
        job.recover()
        XCTAssertEqual(job.status, .waitingForServer)
    }
    func testQueueSurvivesReopenAndDeduplicates() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try QueueStore(root: root)
        let job = MovieJob(sourcePath: "/film.mkv", fingerprint: "same")
        try store.save([job, job])
        let reopened = try QueueStore(root: root)
        XCTAssertEqual(try reopened.load().count, 1)
    }
    func testCorruptedQueueNotSilentlyReset() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data("not JSON".utf8).write(to: root.appendingPathComponent("jobs.json"))
        let store = try QueueStore(root: root)
        XCTAssertThrowsError(try store.load())
    }
    func testDistinctAcceptedJobsNeverDisappearOnSave() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try QueueStore(root: root)
        try store.save([MovieJob(sourcePath: "/film.mkv", fingerprint: "same"), MovieJob(sourcePath: "/film.mkv", fingerprint: "same")])
        XCTAssertEqual(try store.load().count, 2)
    }
}
