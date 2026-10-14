import XCTest
@testable import AutomationCore

final class SMBAuthenticationTests: XCTestCase {
    func testNativeAuthenticationOptionsRemainSilentUnlessRequested() {
        XCTAssertEqual(SMBService.openOptions(allowAuthenticationUI: false)["UIOption"] as? String, "NoUI")
        let interactive = SMBService.openOptions(allowAuthenticationUI: true)
        XCTAssertEqual(interactive["UIOption"] as? String, "AllowUI")
        XCTAssertNil(interactive["Password"])
        XCTAssertNil(interactive["ForceNewSession"])
    }

    func testExplicitRetryAllowsAnotherPromptForOnlyItsShare() {
        var gate = SMBAuthenticationGate()
        let configuration = SMBConfiguration(serverURL: "smb://fixture.invalid/Movies")
        let other = SMBConfiguration(serverURL: "smb://other.invalid/Movies")
        var job = MovieJob(sourcePath: "/synthetic/movie.mkv", fingerprint: "fixture")
        job.validated = true; job.status = .waitingForServer
        XCTAssertTrue(gate.begin(job: job, configuration: configuration, shareIsMounted: false))
        XCTAssertTrue(gate.begin(job: job, configuration: other, shareIsMounted: false))
        gate.allowRetry(configuration: configuration)
        XCTAssertTrue(gate.begin(job: job, configuration: configuration, shareIsMounted: false))
        XCTAssertFalse(gate.begin(job: job, configuration: other, shareIsMounted: false))
    }

    func testAuthenticationPromptsOnlyOncePerServerAcrossWaitingFilms() {
        var gate = SMBAuthenticationGate()
        let configuration = SMBConfiguration(serverURL: "smb://fixture.invalid/Movies")
        var job = MovieJob(sourcePath: "/synthetic/movie.mkv", fingerprint: "fixture")
        job.validated = true; job.status = .waitingForServer
        XCTAssertFalse(gate.begin(job: job, configuration: configuration, shareIsMounted: true))
        XCTAssertTrue(gate.begin(job: job, configuration: configuration, shareIsMounted: false))
        XCTAssertFalse(gate.begin(job: job, configuration: configuration, shareIsMounted: false))
        var next = MovieJob(sourcePath: "/synthetic/next.mkv", fingerprint: "next")
        next.validated = true; next.status = .waitingForServer
        XCTAssertFalse(gate.begin(job: next, configuration: configuration, shareIsMounted: false))
    }

    func testAuthenticationRequiresAValidatedFilmWaitingForServer() {
        var gate = SMBAuthenticationGate()
        let configuration = SMBConfiguration(serverURL: "smb://fixture.invalid/Movies")
        var job = MovieJob(sourcePath: "/synthetic/movie.mkv", fingerprint: "fixture")
        for status in JobStatus.allCases {
            job.status = status
            XCTAssertFalse(gate.begin(job: job, configuration: configuration, shareIsMounted: false))
        }
    }
}
