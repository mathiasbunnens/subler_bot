import XCTest
@testable import AutomationCore

final class FinderSubmissionTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".hermes/cache/scratch/finder-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    private func file(_ name: String) throws -> URL {
        let url = root.appendingPathComponent(name)
        try Data("x".utf8).write(to: url)
        return url
    }

    func testAcceptsMKVWithSpacesAndUnicodeAndUppercaseExtension() throws {
        let a = try file("L’été à Noël (2024).mkv")
        let b = try file("Film 2.MKV")
        let result = FinderSubmission.partition([a, b])
        XCTAssertEqual(result.accepted.map(\.lastPathComponent), ["L’été à Noël (2024).mkv", "Film 2.MKV"])
        XCTAssertTrue(result.rejected.isEmpty)
    }

    func testRejectsOtherTypesFoldersAndMissingFiles() throws {
        let mp4 = try file("film.mp4")
        let folder = root.appendingPathComponent("Dossier.mkv")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let missing = root.appendingPathComponent("absent.mkv")
        let result = FinderSubmission.partition([mp4, folder, missing])
        XCTAssertTrue(result.accepted.isEmpty)
        XCTAssertEqual(result.rejected.count, 3)
    }

    func testDeduplicatesSelection() throws {
        let a = try file("film.mkv")
        let result = FinderSubmission.partition([a, a, root.appendingPathComponent("./film.mkv")])
        XCTAssertEqual(result.accepted.count, 1)
    }

    func testSummary() throws {
        let a = try file("a.mkv"), b = try file("b.mkv"), c = try file("c.avi")
        let result = FinderSubmission.partition([a, b, c])
        XCTAssertEqual(FinderSubmission.summary(result, added: 1), "1 film ajouté à la file · 1 déjà dans la file · ignoré (MKV uniquement) : c.avi")
        XCTAssertEqual(FinderSubmission.summary(.init(), added: 0), "Aucun fichier reçu.")
    }
}
