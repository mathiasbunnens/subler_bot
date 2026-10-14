import XCTest
@testable import AutomationCore

final class LocalPathPolicyTests: XCTestCase {
    func testNetworkPathIsValidButDisplaysPerformanceAdvice() throws {
        let path = "/Volumes/subler-unmounted-\(UUID().uuidString)/Source"
        XCTAssertTrue(LocalPathPolicy.isValidAbsolutePath(path))
        let warning = try XCTUnwrap(LocalPathPolicy.performanceWarning(path))
        XCTAssertTrue(warning.contains("ralentir"))
        XCTAssertTrue(warning.contains("conseillé"))
        XCTAssertNil(LocalPathPolicy.performanceWarning(NSHomeDirectory()))
        XCTAssertFalse(LocalPathPolicy.isValidAbsolutePath("relative/path"))
        XCTAssertFalse(LocalPathPolicy.isValidAbsolutePath("/Source/../Other"))
        XCTAssertFalse(LocalPathPolicy.isValidAbsolutePath("/Source\0Other"))
        // A missing mount is an actual availability failure, never a local substitute.
        XCTAssertThrowsError(try LocalPathPolicy.directoryURL(path))
    }

    func testLocalHomeFoldersAreAccepted() throws {
        let scratch = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".hermes/cache/scratch")
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        XCTAssertTrue(LocalPathPolicy.isOnThisMac(scratch.path))
        // Not yet created: judged by its nearest existing parent.
        XCTAssertTrue(LocalPathPolicy.isOnThisMac(scratch.appendingPathComponent("\(UUID().uuidString)/Temp").path))
    }

    func testServerAndUnsafePathsAreRefused() {
        XCTAssertFalse(LocalPathPolicy.isOnThisMac("/Volumes/Movies/À convertir"))
        XCTAssertFalse(LocalPathPolicy.isOnThisMac("relative/path"))
        XCTAssertFalse(LocalPathPolicy.isOnThisMac(NSHomeDirectory() + "/../other"))
    }

    func testSymlinkToVolumesIsRefused() throws {
        let link = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".hermes/cache/scratch/link-\(UUID().uuidString)")
        try FileManager.default.createSymbolicLink(atPath: link.path, withDestinationPath: "/Volumes/Movies")
        defer { try? FileManager.default.removeItem(at: link) }
        XCTAssertFalse(LocalPathPolicy.isOnThisMac(link.appendingPathComponent("Temp").path))
    }

    func testMountedShareIsRefusedWhenPresent() throws {
        guard let share = SMBConfiguration.mountedSMBShares().first else { throw XCTSkip("No SMB share mounted") }
        XCTAssertFalse(LocalPathPolicy.isOnThisMac(share.mountPoint))
        // Read-only metadata lookup: the warning must not prevent using the mounted path.
        XCTAssertEqual(try LocalPathPolicy.directoryURL(share.mountPoint).path, share.mountPoint)
    }

    func testPublishedMoviePathMatchesTransferLayout() {
        let url = LocalPathPolicy.publishedMovie(shareRoot: URL(fileURLWithPath: "/Volumes/Movies"), movieName: "Dune (2021)")
        XCTAssertEqual(url.path, "/Volumes/Movies/Dune (2021)/Dune (2021).mp4")
    }
}
