import XCTest
@testable import AutomationCore

final class RemainingTimeFormatterTests: XCTestCase {
    func testMinuteAndSecondsFormatting() {
        XCTAssertEqual(RemainingTimeFormatter.string(seconds: 95), "1m35s")
    }
    func testSecondsMinutesAndHoursBoundaries() {
        XCTAssertEqual(RemainingTimeFormatter.string(seconds: 0), "0s")
        XCTAssertEqual(RemainingTimeFormatter.string(seconds: 59), "59s")
        XCTAssertEqual(RemainingTimeFormatter.string(seconds: 60), "1m00s")
        XCTAssertEqual(RemainingTimeFormatter.string(seconds: 59.2), "1m00s")
        XCTAssertEqual(RemainingTimeFormatter.string(seconds: 3723), "1h02m03s")
    }
    func testInvalidEstimatesAreNotDisplayed() {
        XCTAssertNil(RemainingTimeFormatter.string(seconds: -.infinity))
        XCTAssertNil(RemainingTimeFormatter.string(seconds: .infinity))
        XCTAssertNil(RemainingTimeFormatter.string(seconds: .nan))
        XCTAssertNil(RemainingTimeFormatter.string(seconds: -1))
        XCTAssertNil(RemainingTimeFormatter.string(seconds: Double(Int.max)))
    }
}
