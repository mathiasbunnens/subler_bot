import XCTest
@testable import AutomationCore

final class LocalPathPolicyTests: XCTestCase {
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
    }

    func testPublishedMoviePathMatchesTransferLayout() {
        let url = LocalPathPolicy.publishedMovie(shareRoot: URL(fileURLWithPath: "/Volumes/Movies"), movieName: "Dune (2021)")
        XCTAssertEqual(url.path, "/Volumes/Movies/Dune (2021)/Dune (2021).mp4")
    }
}
