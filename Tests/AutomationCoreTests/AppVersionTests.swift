import Foundation
import XCTest
@testable import AutomationCore

final class AppVersionTests: XCTestCase {
    func testMissingOrEmptyMetadataDoesNotClaimAnInstalledVersion() {
        for info: [String: Any]? in [nil, [:], ["CFBundleShortVersionString": "  ", "CFBundleVersion": "2"]] {
            let version = AppVersion(infoDictionary: info)
            XCTAssertEqual(version.label, "Subler Automation — développement (hors bundle)")
            XCTAssertEqual(version.details, "Version indisponible hors bundle application")
        }
    }

    func testMissingBuildIsExplicit() {
        XCTAssertEqual(AppVersion(infoDictionary: ["CFBundleShortVersionString": "7.8.9"]).details,
                       "Version 7.8.9 — build indisponible")
    }

    func testReadsAndFormatsBundleMetadata() {
        let version = AppVersion(infoDictionary: ["CFBundleShortVersionString": "7.8.9", "CFBundleVersion": "42"])
        XCTAssertEqual(version.label, "Subler Automation v7.8.9")
        XCTAssertEqual(version.details, "Version 7.8.9 (build 42)")
    }

    func testReadsRealSourcePlistWithoutDuplicatingItsVersionInTheUI() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let data = try Data(contentsOf: root.appendingPathComponent("Sources/SublerAutomation/Resources/Info.plist"))
        let info = try XCTUnwrap(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
        let version = AppVersion(infoDictionary: info)
        XCTAssertEqual(version.label, "Subler Automation v\(try XCTUnwrap(info["CFBundleShortVersionString"] as? String))")
        XCTAssertEqual(version.details, "Version \(try XCTUnwrap(info["CFBundleShortVersionString"] as? String)) (build \(try XCTUnwrap(info["CFBundleVersion"] as? String)))")
    }
}
