import XCTest
@testable import AutomationCore

final class PosterExtractorTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".hermes/cache/scratch/poster-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    private func ffmpeg() throws -> String {
        let path = ["/opt/homebrew/bin/ffmpeg", "/usr/local/bin/ffmpeg"].first { FileManager.default.isExecutableFile(atPath: $0) }
        guard let path else { throw XCTSkip("ffmpeg required for synthetic artwork fixture") }
        return path
    }

    private func run(_ executable: String, _ arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice; process.standardError = FileHandle.nullDevice
        try process.run(); process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0, arguments.joined(separator: " "))
    }

    func testExtractsEmbeddedCoverIntoJobFolder() async throws {
        let tool = try ffmpeg()
        let cover = root.appendingPathComponent("cover.jpg")
        let movie = root.appendingPathComponent("movie.mp4")
        try run(tool, ["-v", "error", "-f", "lavfi", "-i", "color=c=red:s=64x96:d=1", "-frames:v", "1", cover.path])
        try run(tool, ["-v", "error", "-f", "lavfi", "-i", "testsrc=d=1:s=64x64:r=5", "-i", cover.path,
                       "-map", "0", "-map", "1", "-c:v:0", "libx264", "-c:v:1", "mjpeg",
                       "-disposition:v:1", "attached_pic", movie.path])
        let jobID = UUID()
        let folder = root.appendingPathComponent(jobID.uuidString)
        let poster = await PosterExtractor.extract(from: movie, jobFolder: folder)
        let written = try XCTUnwrap(poster)
        XCTAssertEqual(written.lastPathComponent, "poster.jpg")
        XCTAssertNotNil(NSImageRepresentationCheck.decode(written))
        XCTAssertTrue(PosterExtractor.isOwned(written.path, workRoot: root.path, jobID: jobID))
    }

    func testNoArtworkReturnsNil() async throws {
        let tool = try ffmpeg()
        let movie = root.appendingPathComponent("plain.mp4")
        try run(tool, ["-v", "error", "-f", "lavfi", "-i", "testsrc=d=1:s=64x64:r=5", "-c:v", "libx264", movie.path])
        let poster = await PosterExtractor.extract(from: movie, jobFolder: root.appendingPathComponent(UUID().uuidString))
        XCTAssertNil(poster)
    }

    func testOwnershipRejectsForeignPaths() {
        let id = UUID()
        XCTAssertFalse(PosterExtractor.isOwned("/tmp/poster.jpg", workRoot: "/Users/x/Temp", jobID: id))
        XCTAssertFalse(PosterExtractor.isOwned("/Users/x/Temp/\(id.uuidString)/../other/poster.jpg", workRoot: "/Users/x/Temp", jobID: id))
        XCTAssertFalse(PosterExtractor.isOwned("/Users/x/Temp/\(id.uuidString)/poster.jpg", workRoot: nil, jobID: id))
        XCTAssertTrue(PosterExtractor.isOwned("/Users/x/Temp/\(id.uuidString)/poster.jpg", workRoot: "/Users/x/Temp", jobID: id))
    }

    func testImageSignatures() {
        XCTAssertEqual(PosterExtractor.imageExtension(Data([0xFF, 0xD8, 0xFF, 0xE0])), "jpg")
        XCTAssertEqual(PosterExtractor.imageExtension(Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A])), "png")
        XCTAssertNil(PosterExtractor.imageExtension(Data("<html>".utf8)))
    }
}

import ImageIO
enum NSImageRepresentationCheck {
    static func decode(_ url: URL) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }
}
