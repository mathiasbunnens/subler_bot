import XCTest
import CryptoKit
import Darwin
@testable import AutomationCore

private actor ReplacementOnce {
    var performed = false
    func take() -> Bool {
        guard !performed else { return false }
        performed = true
        return true
    }
}

final class ReplacementFailureTests: XCTestCase {
    private struct Fixture {
        let root: URL
        let source: URL
        let final: URL
        let mount: VerifiedMount
        let snapshot: DestinationSnapshot
        let digest: String
        let job = UUID()
        var directory: URL { final.deletingLastPathComponent() }
    }
    private func fixture(name: String = "Movie") throws -> Fixture {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let directory = root.appendingPathComponent("share").appendingPathComponent(name)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let source = root.appendingPathComponent("validated.mp4"), final = directory.appendingPathComponent(name + ".mp4")
        try Data("old film".utf8).write(to: final)
        let data = Data(repeating: 0xAC, count: 2_100_000)
        try data.write(to: source)
        let mount = VerifiedMount.fixture(root: directory.deletingLastPathComponent())
        return Fixture(root: root, source: source, final: final, mount: mount,
                       snapshot: try XCTUnwrap(DestinationSnapshot.capture(mount: mount, movieName: name)),
                       digest: SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined())
    }
    private func copy(_ f: Fixture, service: TransferService = TransferService(),
                      progress: @escaping @Sendable (TransferProgress) async -> Void = { _ in }) async throws -> URL {
        try await service.copy(source: f.source, mount: f.mount, movieName: f.directory.lastPathComponent,
                               jobID: f.job, replaceExisting: true, replacement: f.snapshot,
                               expectedDigest: f.digest, verify: {}, progress: progress)
    }

    func testWriteDiskFullAndSyncFailuresLeaveOldFilmAndAllForeignFiles() async throws {
        for step in [ReplacementStep.copyChunk, .synchronize, .backupChunk] {
            let f = try fixture()
            defer { try? FileManager.default.removeItem(at: f.root) }
            let foreign = f.directory.appendingPathComponent("foreign.part")
            try Data("foreign".utf8).write(to: foreign)
            let service = TransferService(replacementFault: { point in
                if point == step { throw TransferError.io(step == .synchronize ? EIO : ENOSPC) }
            })
            do { _ = try await copy(f, service: service); XCTFail("Injected I/O failure ignored") }
            catch TransferError.io { }
            XCTAssertEqual(try Data(contentsOf: f.final), Data("old film".utf8))
            XCTAssertEqual(try Data(contentsOf: foreign), Data("foreign".utf8))
            XCTAssertTrue(FileManager.default.fileExists(atPath: f.source.path))
            XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: f.directory.path).contains { $0.hasSuffix(".json") })
        }
    }

    func testNativeRenameFailureRetainsVerifiedBackupAndRestartDoesNotAutoPublish() async throws {
        let f = try fixture()
        defer { try? FileManager.default.removeItem(at: f.root) }
        let service = TransferService(nativeReplacement: { _, _, _ in throw TransferError.io(EIO) })
        do { _ = try await copy(f, service: service); XCTFail("Native failure ignored") }
        catch TransferError.io { }
        XCTAssertEqual(try Data(contentsOf: f.final), Data("old film".utf8))
        let backup = await service.preservedBackup(jobID: f.job)
        XCTAssertEqual(try Data(contentsOf: XCTUnwrap(backup)), Data("old film".utf8))
        let recovered = try await TransferService().recoverReplacement(source: f.source, mount: f.mount, movieName: "Movie", jobID: f.job, expectedDigest: f.digest, verify: {}, progress: { _ in })
        XCTAssertNil(recovered)
        XCTAssertEqual(try Data(contentsOf: f.final), Data("old film".utf8))
    }

    func testInterruptedNativeOperationWithMissingFinalBlocksRestartAndRetainsOldFilm() async throws {
        let f = try fixture()
        defer { try? FileManager.default.removeItem(at: f.root) }
        let service = TransferService(nativeReplacement: { target, _, backup in
            try FileManager.default.moveItem(at: target, to: target.deletingLastPathComponent().appendingPathComponent(backup))
            throw TransferError.io(EIO)
        })
        do { _ = try await copy(f, service: service); XCTFail("Disconnect ignored") }
        catch TransferError.io { }
        let restarted = TransferService()
        do {
            _ = try await restarted.recoverReplacement(source: f.source, mount: f.mount, movieName: "Movie", jobID: f.job, expectedDigest: f.digest, verify: {}, progress: { _ in })
            XCTFail("Missing final must require intervention, not a new publication")
        } catch TransferError.recoveryRequired { }
        let backup = await restarted.preservedBackup(jobID: f.job)
        XCTAssertEqual(try Data(contentsOf: XCTUnwrap(backup)), Data("old film".utf8))
        XCTAssertFalse(FileManager.default.fileExists(atPath: f.final.path))
    }

    func testCorruptionAfterNativeCommitNeverClaimsSuccessAndOriginalIsRecoverable() async throws {
        let f = try fixture()
        defer { try? FileManager.default.removeItem(at: f.root) }
        let service = TransferService(nativeReplacement: { target, stage, backup in
            _ = try FileManager.default.replaceItemAt(target, withItemAt: stage, backupItemName: backup, options: [.usingNewMetadataOnly, .withoutDeletingBackupItem])
            try Data("corrupt".utf8).write(to: target)
        })
        do { _ = try await copy(f, service: service); XCTFail("Corrupt publication accepted") }
        catch TransferError.integrity { }
        let backup = await service.preservedBackup(jobID: f.job)
        XCTAssertEqual(try Data(contentsOf: XCTUnwrap(backup)), Data("old film".utf8))
        XCTAssertEqual(try Data(contentsOf: f.source).count, 2_100_000)
    }

    func testCancellationKeepsOriginalAndOnlyLeavesOwnedStages() async throws {
        let f = try fixture()
        defer { try? FileManager.default.removeItem(at: f.root) }
        let task = Task {
            try await self.copy(f, progress: { sample in
                if sample.bytesCopied > 0 { withUnsafeCurrentTask { $0?.cancel() } }
            })
        }
        do { _ = try await task.value; XCTFail("Cancellation ignored") }
        catch is CancellationError { }
        XCTAssertEqual(try Data(contentsOf: f.final), Data("old film".utf8))
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: f.directory.path).allSatisfy {
            $0 == "Movie.mp4" || $0.hasPrefix(".subler-replace-" + f.job.uuidString + "-")
        })
    }

    func testTargetMutationDuringCopyIsNotOverwritten() async throws {
        let f = try fixture(), once = ReplacementOnce()
        defer { try? FileManager.default.removeItem(at: f.root) }
        do {
            _ = try await copy(f, progress: { sample in
                if sample.bytesCopied > 0, await once.take() {
                    try! Data("third-party version".utf8).write(to: f.final, options: .atomic)
                }
            })
            XCTFail("Changed target accepted")
        } catch TransferError.destinationChanged { } catch TransferError.unsafePath { }
        XCTAssertEqual(try Data(contentsOf: f.final), Data("third-party version".utf8))
    }

    func testDuplicateTransferWhileCopyingIsRejectedAndUnicodeNamePublishes() async throws {
        let f = try fixture(name: "Amélie (2001)"), once = ReplacementOnce(), service = TransferService()
        defer { try? FileManager.default.removeItem(at: f.root) }
        _ = try await copy(f, service: service, progress: { sample in
            if sample.bytesCopied == 0, await once.take() {
                do { _ = try await self.copy(f, service: service); XCTFail("Concurrent transfer accepted") }
                catch TransferError.busy { } catch { XCTFail("Unexpected duplicate error: \(error)") }
            }
        })
        XCTAssertEqual(try Data(contentsOf: f.final), try Data(contentsOf: f.source))
    }

    func testUncoordinatedLastInstructionRaceIsDetectedAndBothOldVersionsRemainRecoverable() async throws {
        let f = try fixture()
        defer { try? FileManager.default.removeItem(at: f.root) }
        let thirdParty = Data("third-party in native-call window".utf8)
        let service = TransferService(nativeReplacement: { target, stage, backup in
            // Deliberately AFTER the last revalidation, inside the native seam.
            // This documents the absence of portable SMB compare-and-swap,
            // not a claim that Foundation can prevent this external race.
            try thirdParty.write(to: target, options: .atomic)
            _ = try FileManager.default.replaceItemAt(target, withItemAt: stage, backupItemName: backup, options: [.usingNewMetadataOnly, .withoutDeletingBackupItem])
        })
        do { _ = try await copy(f, service: service); XCTFail("Third-party exchange must not report success") }
        catch TransferError.destinationChanged { }
        let backup = await service.preservedBackup(jobID: f.job)
        let saved = try XCTUnwrap(backup)
        XCTAssertEqual(try Data(contentsOf: saved), Data("old film".utf8))
        XCTAssertEqual(try Data(contentsOf: URL(fileURLWithPath: saved.path + ".native")), thirdParty)
        // The new bytes ARE at the public path in this unavoidable native-call
        // window. Strict no-displacement certification therefore remains open.
        XCTAssertEqual(try Data(contentsOf: f.final), try Data(contentsOf: f.source))
        do {
            _ = try await TransferService().recoverReplacement(source: f.source, mount: f.mount, movieName: "Movie", jobID: f.job, expectedDigest: f.digest, verify: {}, progress: { _ in })
            XCTFail("A raced native backup must not recover as a successful commit")
        } catch TransferError.recoveryRequired { }
    }

    func testRecoveryRejectsWrongSourceDigestAndCorruptBackupWithoutDeletingAnything() async throws {
        let f = try fixture()
        defer { try? FileManager.default.removeItem(at: f.root) }
        let service = TransferService()
        _ = try await copy(f, service: service)
        let savedBackup = await service.preservedBackup(jobID: f.job)
        let backup = try XCTUnwrap(savedBackup)
        let contents = try Set(FileManager.default.contentsOfDirectory(atPath: f.directory.path))
        let wrongDigest = try await TransferService().recoverReplacement(source: f.source, mount: f.mount, movieName: "Movie", jobID: f.job, expectedDigest: String(repeating: "0", count: 64), verify: {}, progress: { _ in })
        XCTAssertNil(wrongDigest)
        let wrongSource = try await TransferService().recoverReplacement(source: f.root.appendingPathComponent("other.mp4"), mount: f.mount, movieName: "Movie", jobID: f.job, expectedDigest: f.digest, verify: {}, progress: { _ in })
        XCTAssertNil(wrongSource)
        try Data("corrupt backup".utf8).write(to: backup)
        do {
            _ = try await TransferService().recoverReplacement(source: f.source, mount: f.mount, movieName: "Movie", jobID: f.job, expectedDigest: f.digest, verify: {}, progress: { _ in })
            XCTFail("Corrupted backup accepted")
        } catch TransferError.integrity { }
        XCTAssertEqual(try Set(FileManager.default.contentsOfDirectory(atPath: f.directory.path)), contents)
        XCTAssertEqual(try Data(contentsOf: f.final), try Data(contentsOf: f.source))
    }

    func testReplacedRootAndDirectorySymlinkCannotRedirectPublication() async throws {
        for mode in ["root", "symlink"] {
            let f = try fixture(), once = ReplacementOnce()
            defer { try? FileManager.default.removeItem(at: f.root) }
            let saved = f.root.appendingPathComponent("saved")
            do {
                _ = try await copy(f, progress: { sample in
                    if sample.bytesCopied > 0, await once.take() {
                        if mode == "root" {
                            try! FileManager.default.moveItem(at: f.mount.root, to: saved)
                            try! FileManager.default.createDirectory(at: f.mount.root, withIntermediateDirectories: false)
                        } else {
                            try! FileManager.default.moveItem(at: f.directory, to: saved)
                            try! FileManager.default.createSymbolicLink(at: f.directory, withDestinationURL: saved)
                        }
                    }
                })
                XCTFail("Redirected publication accepted")
            } catch SMBError.unavailable { } catch TransferError.unsafePath { }
            let old = mode == "root" ? saved.appendingPathComponent("Movie/Movie.mp4") : saved.appendingPathComponent("Movie.mp4")
            XCTAssertEqual(try Data(contentsOf: old), Data("old film".utf8))
        }
    }
}
