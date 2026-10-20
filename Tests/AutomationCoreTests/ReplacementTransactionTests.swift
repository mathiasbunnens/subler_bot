import XCTest
import CryptoKit
@testable import AutomationCore

final class ReplacementTransactionTests: XCTestCase {
    private func fixture() throws -> (URL, VerifiedMount, URL, URL, DestinationSnapshot, String) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let directory = root.appendingPathComponent("Movie")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let final = directory.appendingPathComponent("Movie.mp4"), source = root.appendingPathComponent("source.mp4")
        try Data("original".utf8).write(to: final)
        let bytes = Data(repeating: 0xAB, count: 1_100_000)
        try bytes.write(to: source)
        let mount = VerifiedMount.fixture(root: root)
        return (root, mount, source, final, try XCTUnwrap(DestinationSnapshot.capture(mount: mount, movieName: "Movie")), SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined())
    }

    func testBooleanWithoutSnapshotIsNotConsent() async throws {
        let (root, mount, source, final, _, digest) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        do {
            _ = try await TransferService().copy(source: source, mount: mount, movieName: "Movie", jobID: UUID(), replaceExisting: true, expectedDigest: digest, verify: {}, progress: { _ in })
            XCTFail("A boolean must not authorize replacement")
        } catch TransferError.destinationChanged { }
        XCTAssertEqual(try Data(contentsOf: final), Data("original".utf8))
    }

    func testRestartRecognizesNativeCommitEvenWhenCallerLostAcknowledgement() async throws {
        let (root, mount, source, final, snapshot, digest) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let job = UUID()
        let service = TransferService(nativeReplacement: { target, stage, backup in
            _ = try FileManager.default.replaceItemAt(target, withItemAt: stage, backupItemName: backup, options: [.usingNewMetadataOnly, .withoutDeletingBackupItem])
            throw TransferError.io(EIO) // Process loses the completion acknowledgement.
        })
        do {
            _ = try await service.copy(source: source, mount: mount, movieName: "Movie", jobID: job, replaceExisting: true, replacement: snapshot, expectedDigest: digest, verify: {}, progress: { _ in })
            XCTFail("Lost acknowledgement must surface")
        } catch TransferError.io { }
        XCTAssertEqual(try Data(contentsOf: final), try Data(contentsOf: source))
        let restarted = TransferService()
        let recovered = try await restarted.recoverReplacement(source: source, mount: mount, movieName: "Movie", jobID: job, expectedDigest: digest, verify: {}, progress: { _ in })
        XCTAssertEqual(recovered, final)
        let backup = await restarted.preservedBackup(jobID: job)
        XCTAssertEqual(try Data(contentsOf: XCTUnwrap(backup)), Data("original".utf8))
        // A different job/digest/source must never inherit this consent.
        let unrelated = try await restarted.recoverReplacement(source: source, mount: mount, movieName: "Movie", jobID: UUID(), expectedDigest: digest, verify: {}, progress: { _ in })
        XCTAssertNil(unrelated)
    }

    func testConfirmedReplacementPublishesValidatedBytesAndPreservesOriginalAndSidecars() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let directory = root.appendingPathComponent("Film (2024)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let final = directory.appendingPathComponent("Film (2024).mp4")
        let source = root.appendingPathComponent("source.mp4")
        let original = Data("original movie".utf8), output = Data(repeating: 0xAB, count: 1_100_000)
        try original.write(to: final); try output.write(to: source)
        let sidecar = directory.appendingPathComponent("subtitle.srt")
        try Data("subtitle".utf8).write(to: sidecar)
        let mount = VerifiedMount.fixture(root: root)
        let snapshot = try XCTUnwrap(DestinationSnapshot.capture(mount: mount, movieName: "Film (2024)"))
        let service = TransferService(), job = UUID()
        let digest = SHA256.hash(data: output).map { String(format: "%02x", $0) }.joined()
        let published = try await service.copy(source: source, mount: mount, movieName: "Film (2024)", jobID: job, replaceExisting: true, replacement: snapshot, expectedDigest: digest, verify: {}, progress: { _ in })
        XCTAssertEqual(published, final)
        XCTAssertEqual(try Data(contentsOf: final), output)
        XCTAssertEqual(try Data(contentsOf: source), output)
        XCTAssertEqual(try Data(contentsOf: sidecar), Data("subtitle".utf8))
        let backup = await service.preservedBackup(jobID: job)
        XCTAssertEqual(try Data(contentsOf: XCTUnwrap(backup)), original)
    }
}
