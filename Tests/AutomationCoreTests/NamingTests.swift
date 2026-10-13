import XCTest
@testable import AutomationCore

final class NamingTests: XCTestCase {
    func testSafeUnicodeMovieName() {
        XCTAssertEqual(MovieNaming.name(title: "  Amélie / Paris: rêvé?  ", year: 2001), "Amélie - Paris- rêvé (2001)")
    }
    func testLengthBudgetIncludesSMBUnicodeDecomposition() {
        let name = MovieNaming.name(title: String(repeating: "é", count: 100), year: 2001)
        XCTAssertLessThanOrEqual(name.decomposedStringWithCanonicalMapping.utf8.count, 180)
    }
}
