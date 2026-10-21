import XCTest
@testable import AutomationCore

@MainActor
final class GracefulTerminationTests: XCTestCase {
    func testRepeatedRequestsDrainOnceBeforeShutdownAndReply() async {
        let termination = GracefulTermination()
        var events: [String] = []
        var release: CheckedContinuation<Void, Never>?
        let started = expectation(description: "drain started")
        let first = termination.request(drain: {
            events.append("drain")
            await withCheckedContinuation { release = $0; started.fulfill() }
        }, finish: { events.append("shutdown") })
        let second = termination.request(drain: { events.append("duplicate") }, finish: {})
        await fulfillment(of: [started], timeout: 2)
        XCTAssertTrue(termination.isRequested)
        XCTAssertEqual(events, ["drain"])
        release?.resume()
        await first.value; await second.value
        XCTAssertEqual(events, ["drain", "shutdown"])
    }
}
