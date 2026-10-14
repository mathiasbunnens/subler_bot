import XCTest
@testable import AutomationCore

final class BatchCounterTests: XCTestCase {
    private func job(_ status: JobStatus, needsSelection: Bool = false) -> MovieJob {
        var value = MovieJob(sourcePath: "/tmp/\(UUID().uuidString).mkv", fingerprint: UUID().uuidString)
        value.status = status; value.needsSelection = needsSelection
        return value
    }

    func testFirstStartOpensBatchAtZeroIgnoringHistory() {
        var counter = BatchCounter()
        XCTAssertEqual(counter.completed, 0)
        counter.jobStarted()
        XCTAssertTrue(counter.isOpen)
        XCTAssertEqual(counter.completed, 0)
    }

    func testCompletionsAccumulateWhileBatchIsHeld() {
        var counter = BatchCounter()
        counter.jobStarted(); counter.recordCompletion()
        counter.workerFinished(remaining: [job(.completed), job(.pending)])
        XCTAssertTrue(counter.isOpen, "Pending work keeps the batch open")
        counter.jobStarted(); counter.recordCompletion()
        XCTAssertEqual(counter.completed, 2)
    }

    func testNewBatchAfterDrainResetsCount() {
        var counter = BatchCounter()
        counter.jobStarted(); counter.recordCompletion()
        counter.workerFinished(remaining: [job(.completed)])
        XCTAssertFalse(counter.isOpen)
        XCTAssertEqual(counter.completed, 1, "Finished batch stays visible until the next one starts")
        counter.jobStarted()
        XCTAssertEqual(counter.completed, 0)
    }

    func testInterventionsDoNotHoldBatchButServerWaitDoes() {
        var counter = BatchCounter()
        counter.jobStarted(); counter.recordCompletion()
        counter.workerFinished(remaining: [job(.failed), job(.paused), job(.pending, needsSelection: true)])
        XCTAssertFalse(counter.isOpen)
        counter.jobStarted(); counter.recordCompletion()
        counter.workerFinished(remaining: [job(.waitingForServer)])
        XCTAssertTrue(counter.isOpen)
    }

    func testFailedJobDoesNotCountAndPauseDoesNotReset() {
        var counter = BatchCounter()
        counter.jobStarted(); counter.recordCompletion()
        counter.workerFinished(remaining: [job(.pending), job(.pending)])
        // A failure finishes the worker without recording a completion.
        counter.jobStarted()
        counter.workerFinished(remaining: [job(.failed), job(.pending)])
        XCTAssertEqual(counter.completed, 1)
        XCTAssertTrue(counter.isOpen)
    }

    func testManualResetKeepsBatchBoundary() {
        var counter = BatchCounter()
        counter.jobStarted(); counter.recordCompletion(); counter.recordCompletion()
        counter.reset()
        XCTAssertEqual(counter.completed, 0)
        XCTAssertTrue(counter.isOpen)
        counter.jobStarted(); counter.recordCompletion()
        XCTAssertEqual(counter.completed, 1)
    }
}
