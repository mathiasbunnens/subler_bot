import Foundation
import XCTest
@testable import AutomationCore

final class SublerBundleTargetTests: XCTestCase {
    private let localInfo: [String: Any] = ["SublerAutomationEngine": "background", "SublerAutomationBackgroundRelativePath": "../Subler Background.app"]
    private let appURL = URL(fileURLWithPath: "/delivery/Subler Automation Local.app")

    func testOrdinaryBundleDefaultsToInstalledAndEnvironmentRemainsCompatible() {
        let normal = SublerTarget(environment: [:], bundleInfo: [:], bundleURL: appURL)
        XCTAssertFalse(normal.isBackground)
        let development = SublerTarget(environment: [SublerTarget.environmentKey: "/dev/Background.app"], bundleInfo: nil, bundleURL: appURL)
        XCTAssertEqual(development.backgroundApplication, "/dev/Background.app")
    }

    func testLocalBundleCannotBeRedirectedByInheritedEnvironment() {
        let target = SublerTarget(environment: [SublerTarget.environmentKey: "/unreviewed/Other.app"], bundleInfo: localInfo, bundleURL: appURL)
        XCTAssertEqual(target.backgroundApplication, "/delivery/Subler Background.app")
    }

    func testInvalidBundleSelectionAndMissingSiblingFailClosed() {
        let cases: [[String: Any]] = [localInfo, ["SublerAutomationBackgroundRelativePath": "../Subler Background.app"], ["SublerAutomationEngine": "typo"],
            ["SublerAutomationEngine": false], ["SublerAutomationEngine": "background"],
            ["SublerAutomationEngine": "background", "SublerAutomationBackgroundRelativePath": "/Applications/Subler.app"]]
        for info in cases {
            let target = SublerTarget(environment: [:], bundleInfo: info, bundleURL: appURL)
            XCTAssertTrue(target.isBackground)
            XCTAssertThrowsError(try target.validatedApplicationURL())
        }
    }

    func testDefaultInitializerUsesActualCurrentBundle() {
        let expected = SublerTarget(environment: ProcessInfo.processInfo.environment,
                                    bundleInfo: Bundle.main.infoDictionary, bundleURL: Bundle.main.bundleURL)
        XCTAssertEqual(SublerTarget().backgroundApplication, expected.backgroundApplication)
    }

    func testSignedLocalBundleSelectsSiblingWithoutEnvironment() {
        let target = SublerTarget(environment: [:], bundleInfo: ["SublerAutomationEngine": "background", "SublerAutomationBackgroundRelativePath": "../Subler Background.app"], bundleURL: URL(fileURLWithPath: "/delivery/Subler Automation Local.app"))
        XCTAssertTrue(target.isBackground)
        XCTAssertEqual(target.backgroundApplication, "/delivery/Subler Background.app")
        XCTAssertEqual(target.bundleIdentifier, "local.sublerautomation.Subler")
    }
}
