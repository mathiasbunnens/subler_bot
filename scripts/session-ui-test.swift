import AppKit
import SwiftUI
import AutomationCore
@MainActor final class JobQueueService: ObservableObject {
    var jobs: [MovieJob] = []
    var currentJob: MovieJob? = nil
    var message: String? = nil
    var symbol = "film"
    var hasCompletedThisSession = false
}
@main struct SessionUITest {
    @MainActor static func main() {
        var completed = MovieJob(sourcePath: "/fixture.mkv", fingerprint: "fixture")
        completed.status = .completed
        precondition(!MenuBarStatusImage.isFinished(jobs: [completed], currentJob: nil, message: nil))
        precondition(MenuBarStatusImage.isFinished(jobs: [completed], currentJob: nil, message: nil, hasCompletedThisSession: true))
        for status in JobStatus.allCases where status != .completed {
            var pending = completed; pending.status = status
            precondition(!MenuBarStatusImage.isFinished(jobs: [completed, pending], currentJob: nil, message: nil, hasCompletedThisSession: true))
        }
        precondition(!MenuBarStatusImage.isFinished(jobs: [completed], currentJob: completed, message: nil, hasCompletedThisSession: true))
        precondition(!MenuBarStatusImage.isFinished(jobs: [completed], currentJob: nil, message: "error", hasCompletedThisSession: true))
        precondition(!MenuBarStatusImage.isFinished(jobs: [], currentJob: nil, message: nil, hasCompletedThisSession: true))
        print("SESSION_BADGE_PASS: no startup badge; current-session success required; pending/active/error/empty suppress badge")
    }
}
