import XCTest
@testable import AutomationCore

final class OutputSafetyTests: XCTestCase {
    func testOwnedFileDigestDetectsModification() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let id = UUID(), folder = root.appendingPathComponent(id.uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let output = folder.appendingPathComponent(UUID().uuidString + ".mp4")
        let source = root.appendingPathComponent("source.mkv")
        try Data("source".utf8).write(to: source)
        try Data("validated bytes".utf8).write(to: output)
        let digest = try await GeneratedOutput.verify(url: output, source: source, root: root, jobID: id)
        XCTAssertFalse(digest.isEmpty)
        try Data("replaced bytes".utf8).write(to: output)
        do {
            _ = try await GeneratedOutput.verify(url: output, source: source, root: root, jobID: id, expectedDigest: digest)
            XCTFail("Changed output must not be transferable")
        } catch { }
    }
    func testOriginalCanNeverBeAcceptedAsGeneratedOutput() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let source = root.appendingPathComponent("original.mkv")
        try Data("original".utf8).write(to: source)
        do {
            _ = try await GeneratedOutput.verify(url: source, source: source, root: root, jobID: UUID())
            XCTFail("Original was accepted for cleanup")
        } catch { }
        XCTAssertEqual(try Data(contentsOf: source), Data("original".utf8))
    }
}
