import Foundation
import XCTest
@testable import AutomationCore

final class EngineDiagnosticTests: XCTestCase {
    func testInstalledLookupPreservesResolvedPath() {
        let app = URL(fileURLWithPath: "/Applications/Subler.app")
        let diagnostic = EngineDiagnostic(bundle: .main, target: SublerTarget(backgroundApplication: nil), installedApplicationURL: app)
        XCTAssertFalse(diagnostic.background)
        XCTAssertTrue(diagnostic.valid)
        XCTAssertNil(diagnostic.error)
        XCTAssertEqual(diagnostic.applicationPath, app.path)
    }

    func testAbsentInstalledLookupIsNotVerified() {
        let diagnostic = EngineDiagnostic(bundle: .main, target: SublerTarget(backgroundApplication: nil), installedApplicationURL: nil)
        XCTAssertFalse(diagnostic.background)
        XCTAssertEqual(diagnostic.targetBundleIdentifier, "org.galad.Subler")
        XCTAssertEqual(diagnostic.applicationPath, "Subler installé introuvable")
        XCTAssertFalse(diagnostic.valid)
        XCTAssertNotNil(diagnostic.error)
        XCTAssertEqual(diagnostic.status, diagnostic.error)
    }

    func testLocalFailureRetainsConfiguredPathWithoutInstalledFallback() {
        let path = "/missing/Background.app"
        let diagnostic = EngineDiagnostic(bundle: .main, target: SublerTarget(backgroundApplication: path),
                                          installedApplicationURL: URL(fileURLWithPath: "/Applications/Subler.app"))
        XCTAssertTrue(diagnostic.background)
        XCTAssertEqual(diagnostic.targetBundleIdentifier, "local.sublerautomation.Subler")
        XCTAssertEqual(diagnostic.applicationPath, path)
        XCTAssertFalse(diagnostic.valid)
        XCTAssertNotNil(diagnostic.error)
    }
}
