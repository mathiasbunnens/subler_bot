import XCTest
import Foundation
@testable import AutomationCore

final class ManualMetadataTests: XCTestCase {
    func testInputValidation() throws {
        let value = try ManualMovieMetadata.parse(title: "  L’été du test  ", year: " 2024 ")
        XCTAssertEqual(value.title, "L’été du test"); XCTAssertEqual(value.year, 2024)
        for title in ["", "   ", "Bad\ntitle", "Bad\u{0}title"] {
            XCTAssertThrowsError(try ManualMovieMetadata.parse(title: title, year: "2024"))
        }
        for year in ["", "24", "020", "0000", "999", "10000", "+2024", "20x4", "２０２４"] {
            XCTAssertThrowsError(try ManualMovieMetadata.parse(title: "Test", year: year))
        }
    }

    func testPropagationAndLegacyDecode() throws {
        var job = MovieJob(sourcePath: "/synthetic/Test.mkv", fingerprint: "fixture")
        let legacy = try JSONEncoder().encode(job)
        XCTAssertNil(try JSONDecoder().decode(MovieJob.self, from: legacy).manualMetadata)
        job.status = .paused; job.needsSelection = true; job.candidateIndex = 9; job.candidateRaw = "stale"
        XCTAssertNotNil(job.metadataWarning)
        let metadata = try ManualMovieMetadata(title: "L’été du test", year: 2024)
        try job.applyManualMetadata(metadata, isActive: false)
        XCTAssertEqual(job.title, metadata.title); XCTAssertEqual(job.year, metadata.year)
        XCTAssertNil(job.candidateIndex); XCTAssertNil(job.candidateRaw)
        XCTAssertFalse(job.validated); XCTAssertNil(job.validatedDigest); XCTAssertFalse(job.needsSelection)
        XCTAssertEqual(job.status, .pending); XCTAssertTrue(job.displayName.contains("2024"))
        let loaded = try JSONDecoder().decode(MovieJob.self, from: JSONEncoder().encode(job))
        XCTAssertEqual(loaded.manualMetadata, metadata); XCTAssertNotNil(loaded.metadataWarning)
        XCTAssertThrowsError(try JSONDecoder().decode(ManualMovieMetadata.self, from: Data("{\"title\":\"\",\"year\":2024}".utf8)))
    }

    func testNoEditingActiveValidatedOrConvertedJobs() throws {
        let metadata = try ManualMovieMetadata(title: "Test", year: 2024)
        var job = MovieJob(sourcePath: "/synthetic/Test.mkv", fingerprint: "fixture")
        job.status = .paused
        XCTAssertThrowsError(try job.applyManualMetadata(metadata, isActive: true))
        job.localPath = "/synthetic/output.mp4"
        XCTAssertThrowsError(try job.applyManualMetadata(metadata, isActive: false))
        job.localPath = nil; job.validated = true
        XCTAssertThrowsError(try job.applyManualMetadata(metadata, isActive: false))
        XCTAssertNil(job.manualMetadata)
    }

    private func fixtures() async throws -> (root: URL, source: URL, output: URL, id: UUID) {
        let scratch = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".hermes/cache/scratch")
        let root = scratch.appendingPathComponent("manual-metadata-\(UUID().uuidString)")
        let id = UUID()
        try FileManager.default.createDirectory(at: root.appendingPathComponent(id.uuidString), withIntermediateDirectories: true)
        let source = root.appendingPathComponent("source.mkv")
        let output = root.appendingPathComponent(id.uuidString).appendingPathComponent("\(UUID().uuidString).mp4")
        guard let ffmpeg = ProcessInfo.processInfo.environment["MANUAL_METADATA_FFMPEG"], FileManager.default.isExecutableFile(atPath: ffmpeg) else {
            throw XCTSkip("Set MANUAL_METADATA_FFMPEG to run synthetic output verification.")
        }
        _ = try await ProcessWorker.run(executable: URL(fileURLWithPath: ffmpeg), arguments: ["-v", "error", "-f", "lavfi", "-i", "color=c=blue:s=64x64:r=25", "-f", "lavfi", "-i", "sine=frequency=440:sample_rate=48000", "-t", "1", "-c:v", "libx264", "-g", "1", "-bf", "0", "-profile:v", "baseline", "-pix_fmt", "yuv420p", "-c:a", "aac", source.path], timeout: 60)
        _ = try await ProcessWorker.run(executable: URL(fileURLWithPath: ffmpeg), arguments: ["-v", "error", "-i", source.path, "-c", "copy", "-metadata", "title=Old title", "-metadata", "date=1999", output.path], timeout: 60)
        return (root, source, output, id)
    }

    func testActualOutputWriteReadbackAndMismatch() async throws {
        let f = try await fixtures()
        defer { try? FileManager.default.removeItem(at: f.root) }
        let metadata = try ManualMovieMetadata(title: "L’été du test", year: 2024)
        do {
            _ = try await MediaValidationService.validate(source: f.source, output: f.output, expected: metadata)
            XCTFail("Old persisted title/year must fail")
        } catch { XCTAssertTrue(error.localizedDescription.contains("Transfert refusé")) }
        let sourceBefore = try FileIdentity.fingerprint(f.source)
        try await ManualMetadataWriter.apply(metadata, source: f.source, output: f.output, root: f.root, jobID: f.id)
        let read = try await MediaValidationService.validate(source: f.source, output: f.output, expected: metadata)
        XCTAssertEqual(read.title, metadata.title); XCTAssertEqual(read.year, 2024)
        XCTAssertEqual(try FileIdentity.fingerprint(f.source), sourceBefore)
        _ = try await GeneratedOutput.verify(url: f.output, source: f.source, root: f.root, jobID: f.id)
        try await ManualMetadataWriter.apply(metadata, source: f.source, output: f.output, root: f.root, jobID: f.id)
        let wrong = try ManualMovieMetadata(title: "Different film", year: 2023)
        do {
            _ = try await MediaValidationService.validate(source: f.source, output: f.output, expected: wrong)
            XCTFail("Different persisted title/year must block transfer")
        } catch { XCTAssertTrue(error.localizedDescription.contains("Transfert refusé")) }
        let probe = try await ProcessWorker.run(executable: URL(fileURLWithPath: "/opt/homebrew/bin/ffprobe"), arguments: ["-v", "error", "-show_entries", "format_tags=title,date:stream=codec_type:format=duration", "-of", "json", f.output.path], timeout: 30)
        print("MANUAL_METADATA_READBACK \(probe)")
        XCTAssertTrue(probe.contains(metadata.title)); XCTAssertTrue(probe.contains("2024"))
    }

    func testRawMKVCannotBecomeManualOutput() async throws {
        let f = try await fixtures()
        defer { try? FileManager.default.removeItem(at: f.root) }
        let metadata = try ManualMovieMetadata(title: "Test", year: 2024)
        try FileManager.default.removeItem(at: f.output)
        try FileManager.default.copyItem(at: f.source, to: f.output)
        do {
            try await ManualMetadataWriter.apply(metadata, source: f.source, output: f.output, root: f.root, jobID: f.id)
            XCTFail("Renamed raw MKV must not be remuxed by the metadata writer")
        } catch { XCTAssertTrue(error.localizedDescription.contains("jamais un MKV brut")) }
    }

    func testFailedValidationPreservesGeneratedOutput() async throws {
        let f = try await fixtures()
        defer { try? FileManager.default.removeItem(at: f.root) }
        let before = try Data(contentsOf: f.output)
        let metadata = try ManualMovieMetadata(title: "Test", year: 2024)
        try FileManager.default.removeItem(at: f.source)
        do {
            try await ManualMetadataWriter.apply(metadata, source: f.source, output: f.output, root: f.root, jobID: f.id)
            XCTFail("Missing source prevents validation and publication")
        } catch { }
        XCTAssertEqual(try Data(contentsOf: f.output), before)
        let remaining = try FileManager.default.contentsOfDirectory(atPath: f.output.deletingLastPathComponent().path)
        XCTAssertEqual(remaining, [f.output.lastPathComponent])
    }

    func testForeignOutputCannotBeRewritten() async throws {
        let f = try await fixtures()
        defer { try? FileManager.default.removeItem(at: f.root) }
        let before = try Data(contentsOf: f.output)
        let metadata = try ManualMovieMetadata(title: "Test", year: 2024)
        do {
            try await ManualMetadataWriter.apply(metadata, source: f.source, output: f.output, root: f.root, jobID: UUID())
            XCTFail("Wrong owner must fail before writing")
        } catch { XCTAssertTrue(error is OutputSafetyError) }
        XCTAssertEqual(try Data(contentsOf: f.output), before)
    }
}
