import XCTest
@testable import AutomationCore

final class EmbeddedEngineOwnershipTests: XCTestCase {
    let url = URL(fileURLWithPath: "/fixture/Automation.app/Contents/Helpers/Subler Background.app")
    func testOnlyExactLaunchedProcessMayBeStopped() {
        var owner = EmbeddedEngineOwnership()
        let process = EngineProcessIdentity(pid: 42, launched: Date(timeIntervalSince1970: 10), url: url)
        XCTAssertFalse(owner.permitsShutdown(expected: url, running: [process]))
        owner.recordLaunch(process)
        XCTAssertTrue(owner.permitsShutdown(expected: url, running: [process]))
        XCTAssertFalse(owner.permitsShutdown(expected: url, running: []))
        XCTAssertFalse(owner.permitsShutdown(expected: url, running: [process, process]))
        XCTAssertFalse(owner.permitsShutdown(expected: URL(fileURLWithPath: "/other.app"), running: [process]))
        XCTAssertFalse(owner.permitsShutdown(expected: url, running: [EngineProcessIdentity(pid: 42, launched: Date(), url: url)]))
        XCTAssertFalse(EmbeddedEngineOwnership().permitsShutdown(expected: url, running: [process]), "A second caller never adopts a pre-existing engine")
    }
}
