import Foundation
import XCTest
@testable import AutomationCore

final class AppVersionTests: XCTestCase {
    func testLocalBuildLabelAndCommitAreVisible() {
        let version = AppVersion(infoDictionary: ["CFBundleShortVersionString": "1.1.0", "CFBundleVersion": "5",
            "CFBundleDisplayName": "Subler Automation Local", "SublerAutomationCommit": "1234567890abcdef"])
        XCTAssertEqual(version.label, "Subler Automation Local · v1.1.0")
        XCTAssertEqual(version.details, "Version 1.1.0 (build 5) · 1234567")
    }

    func testMissingOrEmptyMetadataDoesNotClaimAnInstalledVersion() {
        for info: [String: Any]? in [nil, [:], ["CFBundleShortVersionString": "  ", "CFBundleVersion": "2"]] {
            let version = AppVersion(infoDictionary: info)
            XCTAssertEqual(version.label, "Subler Automation · développement (hors bundle)")
            XCTAssertEqual(version.details, "Version indisponible hors bundle application")
        }
    }

    func testMissingBuildIsExplicit() {
        XCTAssertEqual(AppVersion(infoDictionary: ["CFBundleShortVersionString": "7.8.9"]).details,
                       "Version 7.8.9 — build indisponible")
    }

    func testReadsAndFormatsBundleMetadata() {
        let version = AppVersion(infoDictionary: ["CFBundleShortVersionString": "7.8.9", "CFBundleVersion": "42"])
        XCTAssertEqual(version.label, "Subler Automation · v7.8.9")
        XCTAssertEqual(version.details, "Version 7.8.9 (build 42)")
    }

    func testReadsRealSourcePlistWithoutDuplicatingItsVersionInTheUI() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let data = try Data(contentsOf: root.appendingPathComponent("Sources/SublerAutomation/Resources/Info.plist"))
        let info = try XCTUnwrap(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
        let version = AppVersion(infoDictionary: info)
        XCTAssertEqual(version.label, "Subler Automation · v\(try XCTUnwrap(info["CFBundleShortVersionString"] as? String))")
        XCTAssertEqual(version.details, "Version \(try XCTUnwrap(info["CFBundleShortVersionString"] as? String)) (build \(try XCTUnwrap(info["CFBundleVersion"] as? String)))")
    }
}
