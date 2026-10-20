import XCTest
@testable import AutomationCore

final class ReplacementReviewTests: XCTestCase {
    func testUnsupportedReplacementFailsBeforeIOAndPreservesWholeDestination() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let directory = root.appendingPathComponent("Movie")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let final = directory.appendingPathComponent("Movie.mp4"), sidecar = directory.appendingPathComponent("subtitle.srt")
        try Data("old film".utf8).write(to: final)
        try Data("subtitle".utf8).write(to: sidecar)
        let mount = VerifiedMount.fixture(root: root, allowsReplacement: false)
        let snapshot = try XCTUnwrap(DestinationSnapshot.capture(mount: mount, movieName: "Movie"))
        let service = TransferService(), id = UUID()
        do {
            _ = try await service.copy(source: root.appendingPathComponent("nonexistent-input.mp4"), mount: mount, movieName: "Movie", jobID: id, replaceExisting: true, replacement: snapshot, verify: { XCTFail("No transfer or I/O before capability gate") }, progress: { _ in XCTFail("No copy") })
            XCTFail("Unsupported replacement accepted")
        } catch TransferError.replacementUnavailable { }
        XCTAssertEqual(try Data(contentsOf: final), Data("old film".utf8))
        XCTAssertEqual(try Data(contentsOf: sidecar), Data("subtitle".utf8))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.path), ["Movie"])
        let backup = await service.preservedBackup(jobID: id)
        XCTAssertNil(backup)
    }

    func testChangedConsentFailsBeforeCopyAndDoesNotOverwriteNewVersion() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let directory = root.appendingPathComponent("Movie")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let final = directory.appendingPathComponent("Movie.mp4")
        try Data("reviewed".utf8).write(to: final)
        let mount = VerifiedMount.fixture(root: root)
        let snapshot = try XCTUnwrap(DestinationSnapshot.capture(mount: mount, movieName: "Movie"))
        try Data("different version".utf8).write(to: final, options: .atomic)
        do {
            _ = try await TransferService().copy(source: root.appendingPathComponent("absent.mp4"), mount: mount, movieName: "Movie", jobID: UUID(), replaceExisting: true, replacement: snapshot, verify: { XCTFail("Stale consent entered copy") }, progress: { _ in XCTFail("Stale consent entered copy") })
            XCTFail("Stale consent accepted")
        } catch TransferError.destinationChanged { }
        XCTAssertEqual(try Data(contentsOf: final), Data("different version".utf8))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory.path), ["Movie.mp4"])
    }

    func testConflictKeepsMetadataAndRestartDoesNotAuthorizeReplacement() throws {
        var job = MovieJob(sourcePath: "/fixture.mkv", fingerprint: "original")
        job.title = "Film"; job.year = 2024; job.candidateRaw = "candidate"; job.candidateIndex = 2
        job.status = .paused; job.conflict = true
        let restored = try JSONDecoder().decode(MovieJob.self, from: JSONEncoder().encode(job))
        var recovered = restored; recovered.recover()
        XCTAssertEqual(recovered.status, .paused)
        XCTAssertTrue(recovered.conflict)
        XCTAssertFalse(recovered.canEditMetadata)
        XCTAssertEqual(recovered.title, "Film")
        XCTAssertEqual(recovered.candidateIndex, 2)
    }

    func testExplicitReimportPreservesCompletedHistoryAndWatcherDedup() {
        let reportedName = "The.Super.Mario.Galaxy.Movie.2026.MULTI.VF2.2160p.WEBRip.iT.DV.HDR10+.x265.EAC3.5.1.Atmos2"
        var completed = MovieJob(sourcePath: "/fixture/" + reportedName + ".mkv", fingerprint: "same")
        completed.status = .completed
        XCTAssertTrue(QueueImportPolicy.shouldAdd(path: completed.sourcePath, fingerprint: "same", jobs: [completed], explicit: true))
        XCTAssertFalse(QueueImportPolicy.shouldAdd(path: completed.sourcePath, fingerprint: "same", jobs: [completed], explicit: false))
        var active = completed; active.status = .paused
        XCTAssertFalse(QueueImportPolicy.shouldAdd(path: completed.sourcePath, fingerprint: "same", jobs: [completed, active], explicit: true))
        XCTAssertTrue(QueueImportPolicy.shouldAdd(path: "/other/film.mkv", fingerprint: "other", jobs: [active], explicit: true))
    }

    func testReviewSnapshotRejectsChangedTargetSymlinksAndTraversal() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let directory = root.appendingPathComponent("Film (2024)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent("Film (2024).mp4")
        try Data("old".utf8).write(to: file)
        let mount = VerifiedMount.fixture(root: root)
        let snapshot = try XCTUnwrap(DestinationSnapshot.capture(mount: mount, movieName: "Film (2024)"))
        XCTAssertEqual(snapshot.size, 3)
        XCTAssertEqual(snapshot.path, file.path)
        XCTAssertEqual(snapshot, try DestinationSnapshot.capture(mount: mount, movieName: "Film (2024)"))
        try Data("new version".utf8).write(to: file)
        XCTAssertNotEqual(snapshot, try DestinationSnapshot.capture(mount: mount, movieName: "Film (2024)"))
        try FileManager.default.removeItem(at: file)
        try FileManager.default.createSymbolicLink(at: file, withDestinationURL: root.appendingPathComponent("missing"))
        XCTAssertThrowsError(try DestinationSnapshot.capture(mount: mount, movieName: "Film (2024)"))
        XCTAssertThrowsError(try DestinationSnapshot.capture(mount: mount, movieName: "../escape"))
    }
}
