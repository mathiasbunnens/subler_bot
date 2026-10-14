import XCTest
import CryptoKit
@testable import AutomationCore

private actor ProgressLog {
    var samples: [TransferProgress] = []
    func append(_ value: TransferProgress) { samples.append(value) }
}

private actor VerificationCounter {
    var count = 0
    func check() { count += 1 }
}

private actor VerificationState {
    var lost = false
    func check() throws { if lost { throw SMBError.unavailable } }
    func lose() { lost = true }
}

final class TransferTests: XCTestCase {
    func testDirectorySizeConflictRefusesWithoutRedundantDigestReads() async throws {
        let (root, share, source) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let directory = share.appendingPathComponent("Movie")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        let old = Data([0xAB]), final = directory.appendingPathComponent("Movie.mp4")
        try old.write(to: final)
        let checks = VerificationCounter()
        do {
            _ = try await TransferService(directoryPublication: true).copy(source: source, mount: .fixture(root: share), movieName: "Movie", jobID: UUID(), verify: { await checks.check() }, progress: { _ in
                XCTFail("A known size conflict must not copy or verify bytes")
            })
            XCTFail("Different-size destination accepted")
        } catch TransferError.conflict { }
        let count = await checks.count
        XCTAssertEqual(count, 1, "Size inequality already disproves equality: no local/remote digest scans needed")
        XCTAssertEqual(try Data(contentsOf: final), old)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: share.path), ["Movie"])
        XCTAssertEqual(try Data(contentsOf: source).count, 2_500_000)
    }

    func testDifferentSizeDirectoryReplacementRetainsFullIntegrityAndCancellationChecks() async throws {
        // Size inequality skips only the old-file equality probe, never proof of
        // newly copied bytes or checks required before replacing the old folder.
        for failure in ["digest", "corruption", "source-mutation", "cancellation", "mount-loss"] {
            let (root, share, source) = try fixture()
            defer { try? FileManager.default.removeItem(at: root) }
            let directory = share.appendingPathComponent("Movie")
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
            let old = Data([0xAB]), final = directory.appendingPathComponent("Movie.mp4")
            try old.write(to: final)
            let service = TransferService(directoryPublication: true), job = UUID()
            let state = VerificationState()
            let expected = SHA256.hash(data: try Data(contentsOf: source)).map { String(format: "%02x", $0) }.joined()
            let task = Task {
                try await service.copy(source: source, mount: .fixture(root: share), movieName: "Movie", jobID: job, replaceExisting: true, expectedDigest: failure == "digest" ? "wrong" : expected, verify: { try await state.check() }, progress: { sample in
                    guard sample.verificationBytes == 0 else { return }
                    switch failure {
                    case "corruption":
                        let stage = try! FileManager.default.contentsOfDirectory(at: share, includingPropertiesForKeys: nil).first { $0.pathExtension == "staging" }!
                        let file = try! FileHandle(forWritingTo: stage.appendingPathComponent("Movie.mp4"))
                        try! file.write(contentsOf: Data([0xFF])); try! file.close()
                    case "source-mutation":
                        let file = try! FileHandle(forWritingTo: source)
                        try! file.write(contentsOf: Data([0xFF])); try! file.close()
                    case "cancellation": withUnsafeCurrentTask { $0?.cancel() }
                    case "mount-loss": await state.lose()
                    default: break
                    }
                })
            }
            do {
                _ = try await task.value
                XCTFail("Unsafe replacement accepted: \(failure)")
            } catch TransferError.integrity {
                XCTAssertTrue(["digest", "corruption", "source-mutation"].contains(failure))
            } catch is CancellationError {
                XCTAssertEqual(failure, "cancellation")
            } catch SMBError.unavailable {
                XCTAssertEqual(failure, "mount-loss")
            }
            XCTAssertEqual(try Data(contentsOf: final), old, failure)
            XCTAssertTrue(FileManager.default.fileExists(atPath: source.path), failure)
            let backup = await service.preservedBackup(jobID: job)
            XCTAssertNil(backup, "Failure before publication must not move original: \(failure)")
        }
    }

    func testDirectoryPublicationRejectsCorruptionDuringSingleVerification() async throws {
        let (root, share, source) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        do {
            _ = try await TransferService(directoryPublication: true).copy(source: source, mount: .fixture(root: share), movieName: "Movie", jobID: UUID(), verify: {}, progress: { sample in
                if sample.verificationBytes == 0 {
                    let stage = try! FileManager.default.contentsOfDirectory(at: share, includingPropertiesForKeys: nil).first { $0.lastPathComponent.hasSuffix(".staging") }!
                    let file = try! FileHandle(forWritingTo: stage.appendingPathComponent("Movie.mp4"))
                    try! file.write(contentsOf: Data([0xFF])); try! file.close()
                }
            })
            XCTFail("Corrupt remote bytes must not be published")
        } catch TransferError.integrity { }
        XCTAssertFalse(FileManager.default.fileExists(atPath: share.appendingPathComponent("Movie").path))
        XCTAssertEqual(try Data(contentsOf: source).count, 2_500_000)
    }
    func testDirectoryPublicationVerifiesRemoteExactlyOnceWithProgress() async throws {
        let (root, share, source) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let log = ProgressLog()
        let result = try await TransferService(directoryPublication: true).copy(source: source, mount: .fixture(root: share), movieName: "Movie", jobID: UUID(), verify: {}, progress: { await log.append($0) })
        XCTAssertEqual(try Data(contentsOf: result), try Data(contentsOf: source))
        let samples = await log.samples
        let verification = samples.compactMap(\.verificationBytes)
        XCTAssertEqual(verification.filter { $0 == 0 }.count, 1, "Only one complete remote SHA256 pass")
        XCTAssertEqual(verification.last, 2_500_000)
        XCTAssertTrue(zip(verification, verification.dropFirst()).allSatisfy { $0 <= $1 })
    }
    func testRealSMBUnicodePublication() async throws {
        guard ProcessInfo.processInfo.environment["SUBLER_TEST_SMB"] == "1" else { throw XCTSkip("Opt-in SMB Unicode fixture") }
        let (root, _, source) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let service = SMBService(), config = SMBConfiguration.firstLaunchDefault()
        let mount = try await service.mountedShare(configuration: config)
        let name = "Subler Automation QA Amélie " + UUID().uuidString
        let final = try await TransferService().copy(source: source, mount: mount, movieName: name, jobID: UUID(), verify: {
            _ = try await service.mountedShare(configuration: config)
        }, progress: { _ in })
        XCTAssertEqual(try Data(contentsOf: final), try Data(contentsOf: source))
        try FileManager.default.removeItem(at: final)
        try FileManager.default.removeItem(at: final.deletingLastPathComponent())
        print("REAL_SMB_UNICODE_VERIFIED: accented NFC title published and read back")
    }
    func fixture() throws -> (URL, URL, URL) {
        let root = URL(fileURLWithPath: ProcessInfo.processInfo.environment["TMPDIR"] ?? NSHomeDirectory() + "/.hermes/cache/scratch").appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let share = root.appendingPathComponent("share")
        try FileManager.default.createDirectory(at: share, withIntermediateDirectories: true)
        let source = root.appendingPathComponent("input.mp4")
        try Data((0..<2_500_000).map { UInt8(truncatingIfNeeded: $0) }).write(to: source)
        return (root, share, source)
    }

    func testSameSizeExistingFileComparisonReportsProgress() async throws {
        let (root, share, source) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let directory = share.appendingPathComponent("Movie")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        let final = directory.appendingPathComponent("Movie.mp4")
        let size = try Data(contentsOf: source).count
        try Data(repeating: 0x5A, count: size).write(to: final)
        let log = ProgressLog()
        do {
            _ = try await TransferService().copy(source: source, mount: .fixture(root: share), movieName: "Movie", jobID: UUID(), verify: {}, progress: { await log.append($0) })
            XCTFail("Expected conflict")
        } catch TransferError.conflict {}
        let samples = await log.samples
        // Hashing a multi-GB local and server copy must never look frozen in the menu.
        XCTAssertTrue(samples.contains { $0.verificationBytes == Int64(size) }, "Comparison must report verification progress")
    }

    func testDuplicateRefusesWithoutChangingOriginal() async throws {
        let (root, share, source) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let directory = share.appendingPathComponent("Movie")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        let final = directory.appendingPathComponent("Movie.mp4")
        let original = Data("original".utf8); try original.write(to: final)
        do {
            _ = try await TransferService().copy(source: source, mount: .fixture(root: share), movieName: "Movie", jobID: UUID(), verify: {}, progress: { _ in })
            XCTFail("Expected conflict")
        } catch TransferError.conflict(let url) { XCTAssertEqual(url, final) }
        XCTAssertEqual(try Data(contentsOf: final), original)
    }

    func testRejectsTraversalAndSymlinkDirectory() async throws {
        let (root, share, source) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createSymbolicLink(at: share.appendingPathComponent("Link"), withDestinationURL: root)
        for name in ["../Escape", "Link", ".", "a/b", "a\\b", ""] {
            do {
                _ = try await TransferService().copy(source: source, mount: .fixture(root: share), movieName: name, jobID: UUID(), verify: {}, progress: { _ in })
                XCTFail("Unsafe path accepted: \(name)")
            } catch TransferError.unsafePath {} catch { XCTFail("Wrong error for \(name): \(error)") }
        }
    }

    func testVerifierLossRetainsSourceAndUnrelatedPartial() async throws {
        let (root, share, source) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let directory = share.appendingPathComponent("Movie")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        let unrelated = directory.appendingPathComponent("Movie.mp4.OTHER.part")
        let bytes = Data("unrelated".utf8); try bytes.write(to: unrelated)
        let state = VerificationState()
        do {
            _ = try await TransferService().copy(source: source, mount: .fixture(root: share), movieName: "Movie", jobID: UUID(), verify: { try await state.check() }, progress: { _ in await state.lose() })
            XCTFail("Expected unavailable")
        } catch SMBError.unavailable {}
        XCTAssertEqual(try Data(contentsOf: unrelated), bytes)
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent("Movie.mp4").path))
    }

    func testOriginMatchingDecodesShareAndIgnoresUserButNotHostOrShare() {
        XCTAssertTrue(SMBService.sameShare("//DOMAIN;adminMat@192.168.1.100/Mo%76ies", "smb://192.168.1.100/movies"))
        XCTAssertTrue(SMBService.sameShare("//admin@NAS/Film%20Library", "smb://nas/Film%20Library"))
        XCTAssertFalse(SMBService.sameShare("//admin@192.168.1.101/Movies", "smb://192.168.1.100/Movies"))
        XCTAssertFalse(SMBService.sameShare("//admin@192.168.1.100/Other", "smb://192.168.1.100/Movies"))
    }

    func testLocalDirectoryCannotMasqueradeAsSMBMount() async throws {
        let (root, share, _) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        do {
            _ = try await SMBService().mountedShare(configuration: .init(serverURL: "smb://fixture-invalid.invalid/\(UUID().uuidString)", expectedMountPath: share.path))
            XCTFail("Local directory accepted")
        } catch SMBError.unavailable {}
    }

    func testExplicitReplacementPreservesOldFileAsBackup() async throws {
        let (root, share, source) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let directory = share.appendingPathComponent("Movie")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        let old = Data("keep old file".utf8)
        try old.write(to: directory.appendingPathComponent("Movie.mp4"))
        let service = TransferService(), job = UUID()
        let final = try await service.copy(source: source, mount: .fixture(root: share), movieName: "Movie", jobID: job, replaceExisting: true, verify: {}, progress: { _ in })
        XCTAssertEqual(try Data(contentsOf: final), try Data(contentsOf: source))
        let backup = await service.preservedBackup(jobID: job)
        XCTAssertNotNil(backup)
        if let backup { XCTAssertEqual(try Data(contentsOf: backup), old) }
    }

    func testIdenticalPublishedDestinationIsIdempotent() async throws {
        let (root, share, source) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let service = TransferService(), job = UUID()
        let first = try await service.copy(source: source, mount: .fixture(root: share), movieName: "Movie", jobID: job, verify: {}, progress: { _ in })
        let attributes = try FileManager.default.attributesOfItem(atPath: first.path)
        let second = try await service.copy(source: source, mount: .fixture(root: share), movieName: "Movie", jobID: job, verify: {}, progress: { _ in })
        XCTAssertEqual(first, second)
        XCTAssertEqual(attributes[.systemFileNumber] as? NSNumber, try FileManager.default.attributesOfItem(atPath: second.path)[.systemFileNumber] as? NSNumber)
    }

    func testCancellationKeepsPartialAndRestartOnlyTouchesOwnedPartial() async throws {
        let (root, share, source) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let job = UUID(), service = TransferService()
        let task = Task {
            try await service.copy(source: source, mount: .fixture(root: share), movieName: "Movie", jobID: job, verify: {}, progress: { value in
                if value.bytesCopied > 0 { withUnsafeCurrentTask { $0?.cancel() } }
            })
        }
        do { _ = try await task.value; XCTFail("Cancellation ignored") } catch is CancellationError {}
        let partial = share.appendingPathComponent("Movie/Movie.mp4.\(job.uuidString).part")
        XCTAssertEqual(try Data(contentsOf: partial).count, 1_048_576)
        let other = share.appendingPathComponent("Movie/unrelated.part")
        let sentinel = Data("sentinel".utf8); try sentinel.write(to: other)
        let final = try await service.copy(source: source, mount: .fixture(root: share), movieName: "Movie", jobID: job, verify: {}, progress: { _ in })
        XCTAssertEqual(try Data(contentsOf: final), try Data(contentsOf: source))
        XCTAssertEqual(try Data(contentsOf: other), sentinel)
    }

    func testRejectsSymlinkFinalAndPartial() async throws {
        let (root, share, source) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let directory = share.appendingPathComponent("Movie")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        let job = UUID(), service = TransferService()
        for name in ["Movie.mp4", "Movie.mp4.\(job.uuidString).part"] {
            let link = directory.appendingPathComponent(name)
            try FileManager.default.createSymbolicLink(at: link, withDestinationURL: source)
            do {
                _ = try await service.copy(source: source, mount: .fixture(root: share), movieName: "Movie", jobID: job, verify: {}, progress: { _ in })
                XCTFail("Symlink accepted")
            } catch TransferError.unsafePath {}
            try FileManager.default.removeItem(at: link)
        }
        XCTAssertEqual(try Data(contentsOf: source).count, 2_500_000)
    }

    func testReadbackDetectsCorruptedPartialBeforePublication() async throws {
        let (root, share, source) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let job = UUID()
        let part = share.appendingPathComponent("Movie/Movie.mp4.\(job.uuidString).part")
        do {
            _ = try await TransferService().copy(source: source, mount: .fixture(root: share), movieName: "Movie", jobID: job, verify: {}, progress: { value in
                if value.bytesCopied == value.totalBytes {
                    if let handle = try? FileHandle(forWritingTo: part) { try? handle.write(contentsOf: Data([255])); try? handle.close() }
                }
            })
            XCTFail("Corrupt readback accepted")
        } catch TransferError.integrity {}
        XCTAssertFalse(FileManager.default.fileExists(atPath: share.appendingPathComponent("Movie/Movie.mp4").path))
    }

    func testReplacedRootIsRejectedBeforeNextBlock() async throws {
        let (root, share, source) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        do {
            _ = try await TransferService().copy(source: source, mount: .fixture(root: share), movieName: "Movie", jobID: UUID(), verify: {}, progress: { value in
                if value.bytesCopied == 1_048_576 {
                    try? FileManager.default.moveItem(at: share, to: root.appendingPathComponent("old-share"))
                    try? FileManager.default.createDirectory(at: share, withIntermediateDirectories: false)
                }
            })
            XCTFail("Replaced root accepted")
        } catch SMBError.unavailable {}
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: share.path), [])
    }

    func testReplacementRollsBackIfVerificationFailsAfterBackupMove() async throws {
        let (root, share, source) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let directory = share.appendingPathComponent("Movie")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        let final = directory.appendingPathComponent("Movie.mp4"), old = Data("old movie".utf8)
        try old.write(to: final)
        let service = TransferService(), job = UUID()
        do {
            _ = try await service.copy(source: source, mount: .fixture(root: share), movieName: "Movie", jobID: job, replaceExisting: true, verify: {
                let files = try FileManager.default.contentsOfDirectory(atPath: directory.path)
                if files.contains(where: { $0.hasSuffix(".backup") }) { throw SMBError.unavailable }
            }, progress: { _ in })
            XCTFail("Expected failure after backup")
        } catch SMBError.unavailable {}
        XCTAssertEqual(try Data(contentsOf: final), old)
        let backup = await service.preservedBackup(jobID: job)
        XCTAssertNil(backup)
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
    }

    func testMutationAfterBackupCannotPublishUnverifiedBytes() async throws {
        let (root, share, source) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let directory = share.appendingPathComponent("Movie")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        let final = directory.appendingPathComponent("Movie.mp4"), old = Data("old movie".utf8), job = UUID()
        try old.write(to: final)
        let part = directory.appendingPathComponent("Movie.mp4.\(job.uuidString).part")
        do {
            _ = try await TransferService().copy(source: source, mount: .fixture(root: share), movieName: "Movie", jobID: job, replaceExisting: true, verify: {
                if try FileManager.default.contentsOfDirectory(atPath: directory.path).contains(where: { $0.hasSuffix(".backup") }) {
                    let handle = try FileHandle(forWritingTo: part)
                    try handle.write(contentsOf: Data([255])); try handle.close()
                }
            }, progress: { _ in })
            XCTFail("Mutation after checksum accepted")
        } catch TransferError.integrity {}
        XCTAssertEqual(try Data(contentsOf: final), old)
    }

    func testSourceCannotBeTruncatedWhenItIsTheOwnedPartial() async throws {
        let (root, share, source) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let directory = share.appendingPathComponent("Movie"), job = UUID()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        let part = directory.appendingPathComponent("Movie.mp4.\(job.uuidString).part")
        try FileManager.default.copyItem(at: source, to: part)
        do {
            _ = try await TransferService().copy(source: part, mount: .fixture(root: share), movieName: "Movie", jobID: job, verify: {}, progress: { _ in })
            XCTFail("Source partial accepted")
        } catch TransferError.unsafePath {}
        XCTAssertEqual(try Data(contentsOf: part), try Data(contentsOf: source))
    }

    func testChunkedCopyReportsRealBytesAndMatchesSHA256() async throws {
        let (root, share, source) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let log = ProgressLog()
        let service = TransferService()
        let result = try await service.copy(source: source, mount: .fixture(root: share), movieName: "Movie", jobID: UUID(), verify: {}, progress: { await log.append($0) })
        XCTAssertEqual(result.path, share.appendingPathComponent("Movie/Movie.mp4").path)
        XCTAssertEqual(SHA256.hash(data: try Data(contentsOf: result)), SHA256.hash(data: try Data(contentsOf: source)))
        let samples = await log.samples
        XCTAssertGreaterThan(samples.count, 2)
        XCTAssertEqual(samples.last?.bytesCopied, 2_500_000)
        XCTAssertEqual(samples.last?.fraction, 1)
        XCTAssertTrue(zip(samples, samples.dropFirst()).allSatisfy { $0.bytesCopied <= $1.bytesCopied })
    }
    func testUnvalidatedSourceDigestNeverPublishes() async throws {
        let (root, share, source) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        do {
            _ = try await TransferService().copy(source: source, mount: .fixture(root: share), movieName: "Movie", jobID: UUID(), expectedDigest: "incorrect", verify: {}, progress: { _ in })
            XCTFail("Unvalidated bytes published")
        } catch TransferError.integrity { }
        XCTAssertFalse(FileManager.default.fileExists(atPath: share.appendingPathComponent("Movie/Movie.mp4").path))
    }
    func testDirectoryPublicationRejectsExistingEmptyFolder() async throws {
        let (root, share, source) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let directory = share.appendingPathComponent("Movie")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        do {
            _ = try await TransferService(directoryPublication: true).copy(source: source, mount: .fixture(root: share), movieName: "Movie", jobID: UUID(), verify: {}, progress: { _ in })
            XCTFail("Existing empty directory accepted")
        } catch TransferError.conflict { }
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory.path), [])
    }

    func testDirectoryPublicationRefusesConcurrentNonemptyTarget() async throws {
        let (root, share, source) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let directory = share.appendingPathComponent("Movie"), final = directory.appendingPathComponent("Movie.mp4")
        let sentinel = Data("concurrent film".utf8)
        do {
            _ = try await TransferService(directoryPublication: true).copy(source: source, mount: .fixture(root: share), movieName: "Movie", jobID: UUID(), verify: {
                let stages = try FileManager.default.contentsOfDirectory(at: share, includingPropertiesForKeys: nil).filter { $0.pathExtension == "staging" }
                if stages.contains(where: { FileManager.default.fileExists(atPath: $0.appendingPathComponent("Movie.mp4").path) }), !FileManager.default.fileExists(atPath: directory.path) {
                    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
                    try sentinel.write(to: final)
                }
            }, progress: { _ in })
            XCTFail("Concurrent film overwritten")
        } catch TransferError.conflict { }
        XCTAssertEqual(try Data(contentsOf: final), sentinel)
    }

    func testDirectoryReplacementRollbackPreservesWholeFolder() async throws {
        let (root, share, source) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let directory = share.appendingPathComponent("Movie")
        try FileManager.default.createDirectory(at: directory.appendingPathComponent("extras"), withIntermediateDirectories: true)
        let old = Data("old film".utf8), sidecar = Data("original subtitle".utf8)
        try old.write(to: directory.appendingPathComponent("Movie.mp4"))
        try sidecar.write(to: directory.appendingPathComponent("extras/subtitle.srt"))
        let service = TransferService(directoryPublication: true), job = UUID()
        do {
            _ = try await service.copy(source: source, mount: .fixture(root: share), movieName: "Movie", jobID: job, replaceExisting: true, verify: {
                let backups = try FileManager.default.contentsOfDirectory(at: share, includingPropertiesForKeys: nil).filter { $0.pathExtension == "backup" }
                if backups.contains(where: { FileManager.default.fileExists(atPath: $0.appendingPathComponent("Movie.mp4").path) }) { throw SMBError.unavailable }
            }, progress: { _ in })
            XCTFail("Expected post-backup verifier failure")
        } catch SMBError.unavailable { }
        XCTAssertEqual(try Data(contentsOf: directory.appendingPathComponent("Movie.mp4")), old)
        XCTAssertEqual(try Data(contentsOf: directory.appendingPathComponent("extras/subtitle.srt")), sidecar)
        let backup = await service.preservedBackup(jobID: job)
        XCTAssertNil(backup)
    }

    func testDirectoryReplacementConcurrentFilmKeepsBackupRecoverable() async throws {
        let (root, share, source) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let directory = share.appendingPathComponent("Movie"), final = directory.appendingPathComponent("Movie.mp4")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        let original = Data("original film".utf8), competitor = Data("competing film".utf8)
        try original.write(to: final)
        let service = TransferService(directoryPublication: true), job = UUID()
        do {
            _ = try await service.copy(source: source, mount: .fixture(root: share), movieName: "Movie", jobID: job, replaceExisting: true, verify: {
                let moved = try FileManager.default.contentsOfDirectory(at: share, includingPropertiesForKeys: nil).contains { $0.pathExtension == "backup" && FileManager.default.fileExists(atPath: $0.appendingPathComponent("Movie.mp4").path) }
                if moved, !FileManager.default.fileExists(atPath: directory.path) {
                    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
                    try competitor.write(to: final)
                }
            }, progress: { _ in })
            XCTFail("Directory rename overwrote a nonempty competitor")
        } catch TransferError.conflict { }
        XCTAssertEqual(try Data(contentsOf: final), competitor)
        let backup = await service.preservedBackup(jobID: job)
        let saved = try XCTUnwrap(backup)
        XCTAssertEqual(try Data(contentsOf: saved.appendingPathComponent("Movie.mp4")), original)
    }

    func testDirectoryPublicationDigestValidationAndIdempotence() async throws {
        let (root, share, source) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let service = TransferService(directoryPublication: true), job = UUID()
        do {
            _ = try await service.copy(source: source, mount: .fixture(root: share), movieName: "Movie", jobID: job, expectedDigest: "wrong", verify: {}, progress: { _ in })
            XCTFail("Wrong expected digest accepted")
        } catch TransferError.integrity { }
        XCTAssertFalse(FileManager.default.fileExists(atPath: share.appendingPathComponent("Movie").path))
        let expected = SHA256.hash(data: try Data(contentsOf: source)).map { String(format: "%02x", $0) }.joined()
        let first = try await service.copy(source: source, mount: .fixture(root: share), movieName: "Movie", jobID: job, expectedDigest: expected, verify: {}, progress: { _ in })
        let identity = try FileManager.default.attributesOfItem(atPath: first.path)[.systemFileNumber] as? NSNumber
        let second = try await service.copy(source: source, mount: .fixture(root: share), movieName: "Movie", jobID: job, expectedDigest: expected, verify: {}, progress: { _ in })
        XCTAssertEqual(first, second)
        XCTAssertEqual(identity, try FileManager.default.attributesOfItem(atPath: second.path)[.systemFileNumber] as? NSNumber)
    }

    func testRealSMBReplacementPreservesEntireOwnedFixture() async throws {
        guard ProcessInfo.processInfo.environment["SUBLER_TEST_SMB"] == "1" else { throw XCTSkip("Opt-in SMB replacement") }
        let (root, _, source) = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let mount = try await SMBService().mountedShare(configuration: .init())
        let name = "Subler Automation QA " + UUID().uuidString
        let directory = mount.root.appendingPathComponent(name), final = directory.appendingPathComponent(name + ".mp4")
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.path))
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        let original = Data("owned original fixture".utf8), sidecar = Data("owned subtitle".utf8)
        try original.write(to: final)
        try sidecar.write(to: directory.appendingPathComponent("fixture.srt"))
        print("REAL_SMB_REPLACEMENT_FIXTURE: \(directory.path)")
        let service = TransferService(), job = UUID()
        let expected = SHA256.hash(data: try Data(contentsOf: source)).map { String(format: "%02x", $0) }.joined()
        let result = try await service.copy(source: source, mount: mount, movieName: name, jobID: job, replaceExisting: true, expectedDigest: expected, verify: {}, progress: { _ in })
        XCTAssertEqual(SHA256.hash(data: try Data(contentsOf: result)).map { String(format: "%02x", $0) }.joined(), expected)
        let backup = await service.preservedBackup(jobID: job)
        let saved = try XCTUnwrap(backup)
        XCTAssertEqual(try Data(contentsOf: saved.appendingPathComponent(name + ".mp4")), original)
        XCTAssertEqual(try Data(contentsOf: saved.appendingPathComponent("fixture.srt")), sidecar)
        // No recursive deletion; refuse cleanup if any foreign child appeared.
        guard try FileManager.default.contentsOfDirectory(atPath: directory.path) == [name + ".mp4"],
              Set(try FileManager.default.contentsOfDirectory(atPath: saved.path)) == Set([name + ".mp4", "fixture.srt"]) else { throw TransferError.unsafePath }
        try FileManager.default.removeItem(at: result)
        try FileManager.default.removeItem(at: directory)
        try FileManager.default.removeItem(at: saved.appendingPathComponent(name + ".mp4"))
        try FileManager.default.removeItem(at: saved.appendingPathComponent("fixture.srt"))
        try FileManager.default.removeItem(at: saved)
        XCTAssertFalse(FileManager.default.fileExists(atPath: saved.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.path))
        print("REAL_SMB_REPLACEMENT_VERIFIED: directory backup preserved film + subtitle; owned fixtures cleaned")
    }

    func testRealSMBTransferIntoUniqueTestDirectory() async throws {
        guard ProcessInfo.processInfo.environment["SUBLER_TEST_SMB"] == "1" else { throw XCTSkip("Opt-in real SMB fixture transfer") }
        let (root, _, source) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let service = SMBService(), configuration = SMBConfiguration.firstLaunchDefault()
        let mount = try await service.mountedShare(configuration: configuration)
        let name = "Subler Automation QA " + UUID().uuidString
        let directory = mount.root.appendingPathComponent(name)
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.path))
        let log = ProgressLog()
        let expected = SHA256.hash(data: try Data(contentsOf: source)).map { String(format: "%02x", $0) }.joined()
        let final = try await TransferService().copy(source: source, mount: mount, movieName: name, jobID: UUID(), expectedDigest: expected, verify: {
            let current = try await service.mountedShare(configuration: configuration)
            guard current.root == mount.root, current.origin == mount.origin else { throw SMBError.unavailable }
        }, progress: { await log.append($0) })
        XCTAssertEqual(SHA256.hash(data: try Data(contentsOf: final)).map { String(format: "%02x", $0) }.joined(), expected)
        let samples = await log.samples
        XCTAssertEqual(samples.last?.bytesCopied, 2_500_000)
        let current = try await service.mountedShare(configuration: configuration)
        guard current.root == mount.root, current.origin == mount.origin else { throw SMBError.unavailable }
        // Only this invocation's UUID fixture, created after proving it did not exist.
        try FileManager.default.removeItem(at: final)
        try FileManager.default.removeItem(at: directory)
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.path))
        print("REAL_SMB_TRANSFER_VERIFIED: \(mount.origin) bytes=2500000 samples=\(samples.count); unique fixture cleaned")
    }
}
