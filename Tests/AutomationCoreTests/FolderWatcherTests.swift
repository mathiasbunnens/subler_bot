import XCTest
@testable import AutomationCore

final class FolderWatcherTests: XCTestCase {
    func testRequiresQuietPeriodAndRestartsOnSizeChange() {
        var tracker = FileStabilityTracker()
        let time = Date(timeIntervalSince1970: 1000)
        XCTAssertFalse(tracker.observe(path: "test.mkv", size: 100, modified: time, now: time))
        XCTAssertFalse(tracker.observe(path: "test.mkv", size: 100, modified: time, now: time.addingTimeInterval(59)))
        XCTAssertTrue(tracker.observe(path: "test.mkv", size: 100, modified: time, now: time.addingTimeInterval(61)))
        XCTAssertFalse(tracker.observe(path: "test.mkv", size: 200, modified: time.addingTimeInterval(62), now: time.addingTimeInterval(62)))
    }
}
