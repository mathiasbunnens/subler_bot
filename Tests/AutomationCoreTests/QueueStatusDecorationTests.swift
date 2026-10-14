import XCTest
@testable import AutomationCore

final class QueueStatusDecorationTests: XCTestCase {
    private func decoration(_ jobs: [MovieJob], active: MovieJob? = nil, completed: Bool = true, message: String? = nil) -> QueueStatusDecoration {
        QueueStatusDecoration.resolve(jobs: jobs, currentJob: active, message: message, hasCompletedThisSession: completed)
    }
    private func job(_ status: JobStatus, selection: Bool = false) -> MovieJob {
        var job = MovieJob(sourcePath: "/fixture/movie.mkv", fingerprint: "fixture")
        job.status = status; job.needsSelection = selection
        return job
    }
    func testEmptyQueue() { XCTAssertEqual(decoration([]), .none) }
    func testMetadataConfirmation() {
        let result = decoration([job(.paused, selection: true)], completed: false)
        XCTAssertEqual(result, .metadataConfirmation)
        XCTAssertEqual(result.accessibilityDescription, "Métadonnées à confirmer")
        XCTAssertEqual(result.dockBadgeLabel, "!")
    }
    func testMetadataConfirmationDuringOtherWork() {
        for status in [JobStatus.converting, .transferring] {
            let active = job(status)
            XCTAssertEqual(decoration([job(.paused, selection: true), active], active: active), .metadataConfirmation)
        }
    }
    func testFailedJobIsNotMetadataConfirmation() {
        XCTAssertEqual(decoration([job(.failed)]), .none)
        XCTAssertNil(decoration([job(.failed)]).dockBadgeLabel)
        XCTAssertEqual(decoration([job(.failed, selection: true)]), .metadataConfirmation)
    }
    func testFinishedRequiresSessionCompletionAndNoIntervention() {
        XCTAssertEqual(decoration([job(.completed)]), .finished)
        XCTAssertEqual(decoration([job(.completed)], completed: false), .none)
        XCTAssertEqual(decoration([job(.completed)], message: "Error"), .none)
        XCTAssertEqual(decoration([job(.completed, selection: true)]), .metadataConfirmation)
        XCTAssertNil(decoration([job(.completed)]).dockBadgeLabel)
    }
    func testConfirmationClearsAndManualMetadataAdviceDoesNotWarn() throws {
        var value = job(.paused, selection: true)
        XCTAssertEqual(decoration([value]), .metadataConfirmation)
        value.needsSelection = false
        XCTAssertEqual(decoration([value]), .none)
        // The manual-metadata notice is informational, not missing confirmation.
        let metadata = try ManualMovieMetadata(title: "Fixture", year: 2024)
        try value.applyManualMetadata(metadata, isActive: false)
        XCTAssertNotNil(value.metadataWarning)
        XCTAssertEqual(decoration([value]), .none)
    }
}
