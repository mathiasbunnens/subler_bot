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

    func testEnvironmentOverridePresenceAndInvalidEmbeddedPrecedence() {
        for path in ["", "relative.app", "/missing/Background.app"] {
            let target = SublerTarget(environment: [SublerTarget.environmentKey: path], bundleInfo: [:], bundleURL: appURL)
            XCTAssertTrue(target.isBackground)
            XCTAssertEqual(target.backgroundApplication, path)
            XCTAssertThrowsError(try target.validatedApplicationURL())
        }
        let malformed: [[String: Any]] = [
            ["SublerAutomationEngine": ""], ["SublerAutomationEngine": 2],
            ["SublerAutomationBackgroundRelativePath": ""],
            ["SublerAutomationEngine": "background", "SublerAutomationBackgroundRelativePath": false]]
        for info in malformed {
            let target = SublerTarget(environment: [SublerTarget.environmentKey: "/dev/Background.app"], bundleInfo: info, bundleURL: appURL)
            XCTAssertEqual(target.backgroundApplication, "")
            XCTAssertThrowsError(try target.validatedApplicationURL())
        }
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

    func testEmbeddedBundleMovesWithCallerAndIgnoresEnvironment() {
        let info: [String: Any] = ["SublerAutomationEngine": "background",
            "SublerAutomationBackgroundRelativePath": "Contents/Helpers/Subler Background.app"]
        for location in ["/Applications/Subler Automation.app", "/scratch/Applications déplacées/Subler Automation.app"] {
            let target = SublerTarget(environment: [SublerTarget.environmentKey: "/old/Subler Background.app"],
                                      bundleInfo: info, bundleURL: URL(fileURLWithPath: location))
            XCTAssertEqual(target.backgroundApplication, location + "/Contents/Helpers/Subler Background.app")
            XCTAssertThrowsError(try target.validatedApplicationURL(runningApplicationURLs: { [] }))
        }
    }

    func testLocalMetadataWithoutUsableExecutableFailsClosed() throws {
        let root = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".hermes/cache/scratch").appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let caller = root.appendingPathComponent("Applications déplacées/Subler Automation.app")
        let app = caller.appendingPathComponent("Contents/Helpers/Subler Background.app")
        let macOS = app.appendingPathComponent("Contents/MacOS")
        try FileManager.default.createDirectory(at: macOS, withIntermediateDirectories: true)
        let info: [String: Any] = ["CFBundleIdentifier": "local.sublerautomation.Subler",
            "CFBundleExecutable": "FixtureEngine", "CFBundlePackageType": "APPL",
            "SublerAutomationBackgroundProtocol": "2", "LSBackgroundOnly": true]
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
            .write(to: app.appendingPathComponent("Contents/Info.plist"))
        let target = SublerTarget(environment: [:], bundleInfo: ["SublerAutomationEngine": "background",
            "SublerAutomationBackgroundRelativePath": "Contents/Helpers/Subler Background.app"], bundleURL: caller)
        XCTAssertTrue(target.isBackground)
        XCTAssertEqual(target.bundleIdentifier, "local.sublerautomation.Subler")
        XCTAssertThrowsError(try target.validatedApplicationURL(runningApplicationURLs: { [] }), "Metadata alone is not a usable engine")
        let executable = macOS.appendingPathComponent("FixtureEngine")
        try Data("#!/bin/sh\nexit 0\n".utf8).write(to: executable)
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: executable.path)
        XCTAssertThrowsError(try target.validatedApplicationURL(runningApplicationURLs: { [] }), "Non-executable file must be refused")
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
        XCTAssertEqual(try target.validatedApplicationURL(runningApplicationURLs: { [] })?.path, app.path)
        XCTAssertThrowsError(try target.validatedApplicationURL(runningApplicationURLs: { [root.appendingPathComponent("Old.app")] }))
        try FileManager.default.removeItem(at: executable)
        try FileManager.default.createDirectory(at: executable, withIntermediateDirectories: false)
        XCTAssertThrowsError(try target.validatedApplicationURL(runningApplicationURLs: { [] }), "An executable directory is not an engine")
    }

    func testSignedLocalBundleSelectsSiblingWithoutEnvironment() {
        let target = SublerTarget(environment: [:], bundleInfo: ["SublerAutomationEngine": "background", "SublerAutomationBackgroundRelativePath": "../Subler Background.app"], bundleURL: URL(fileURLWithPath: "/delivery/Subler Automation Local.app"))
        XCTAssertTrue(target.isBackground)
        XCTAssertEqual(target.backgroundApplication, "/delivery/Subler Background.app")
        XCTAssertEqual(target.bundleIdentifier, "local.sublerautomation.Subler")
    }
}
