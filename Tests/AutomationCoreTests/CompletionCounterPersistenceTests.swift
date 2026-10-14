import XCTest
@testable import AutomationCore

final class CompletionCounterPersistenceTests: XCTestCase {
    private func fixture(_ body: (URL) throws -> Void) throws {
        let root = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".hermes/cache/scratch/completion-counter-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try body(root)
    }
    func testAbsentFileStartsAtZeroWithoutCreatingIt() throws {
        try fixture { root in
            XCTAssertEqual(try CompletionCounterStore(root: root).load(), 0)
            XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("completion-counter.json").path))
        }
    }
    func testIncrementAndRelaunchPreserveCountAcrossBatches() throws {
        try fixture { root in
            let store = try CompletionCounterStore(root: root)
            XCTAssertEqual(try store.recordCompletion(), 1)
            XCTAssertEqual(try store.recordCompletion(), 2)
            let reopened = try CompletionCounterStore(root: root)
            var batch = BatchCounter(completed: try reopened.load())
            batch.jobStarted(); batch.workerFinished(remaining: []); batch.jobStarted()
            XCTAssertEqual(batch.completed, 2)
            XCTAssertEqual(try reopened.recordCompletion(), 3)
        }
    }
    func testManualResetPersistsAndNeverChangesHistory() throws {
        try fixture { root in
            let queue = try QueueStore(root: root)
            var job = MovieJob(sourcePath: "/synthetic.mkv", fingerprint: "fixture")
            job.status = .completed
            try queue.save([job])
            let history = try Data(contentsOf: root.appendingPathComponent("jobs.json"))
            let store = try CompletionCounterStore(root: root)
            XCTAssertEqual(try store.load(), 0, "Completed history must not seed the counter")
            try store.recordCompletion(); try store.reset()
            XCTAssertEqual(try CompletionCounterStore(root: root).load(), 0)
            XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("jobs.json")), history)
            XCTAssertEqual(try store.recordCompletion(), 1)
        }
    }
    func testCorruptionThrowsAndCannotBeOverwritten() throws {
        try fixture { root in
            let file = root.appendingPathComponent("completion-counter.json")
            for text in ["not JSON", "{}", "{\"completed\":-1}", "{\"completed\":1.5}"] {
                let bytes = Data(text.utf8)
                try bytes.write(to: file)
                let store = try CompletionCounterStore(root: root)
                XCTAssertThrowsError(try store.load())
                XCTAssertThrowsError(try store.recordCompletion())
                XCTAssertThrowsError(try store.reset())
                XCTAssertEqual(try Data(contentsOf: file), bytes)
            }
        }
    }
    func testFailedWritePreservesDurableCount() throws {
        try fixture { root in
            let store = try CompletionCounterStore(root: root)
            try store.recordCompletion()
            let failing = try CompletionCounterStore(root: root, writer: { _, _ in throw CocoaError(.fileWriteNoPermission) })
            XCTAssertThrowsError(try failing.recordCompletion())
            XCTAssertThrowsError(try failing.reset())
            XCTAssertEqual(try CompletionCounterStore(root: root).load(), 1)
            let noWrite = try CompletionCounterStore(root: root, writer: { _, _ in })
            XCTAssertThrowsError(try noWrite.recordCompletion())
        }
    }
    func testOverflowThrowsWithoutChangingFile() throws {
        try fixture { root in
            let file = root.appendingPathComponent("completion-counter.json")
            let bytes = Data("{\"completed\":\(Int.max)}".utf8)
            try bytes.write(to: file)
            XCTAssertThrowsError(try CompletionCounterStore(root: root).recordCompletion())
            XCTAssertEqual(try Data(contentsOf: file), bytes)
        }
    }
}
