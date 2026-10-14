import Foundation


public enum ManualMetadataWriter {
    /// Only rewrites an owned, generated MP4. The source is never an export target.
    /// Validate the staged file before atomically replacing the generated output.
    public static func apply(_ metadata: ManualMovieMetadata, source: URL, output: URL, root: URL, jobID: UUID) async throws {
        let originalDigest = try await GeneratedOutput.verify(url: output, source: source, root: root, jobID: jobID)
        let handle = try FileHandle(forReadingFrom: output)
        let header = try handle.read(upToCount: 12) ?? Data()
        try handle.close()
        guard header.count == 12, String(decoding: header[4..<8], as: UTF8.self) == "ftyp",
              String(decoding: header[8..<12], as: UTF8.self) != "qt  " else {
            throw AutomationServiceError.message("L’écriture manuelle exige un MP4 déjà converti, jamais un MKV brut. Transfert refusé.")
        }
        // AVAssetExportSession silently dropped the release-date atom in a real fixture.
        // Require a real tag writer; never treat an in-memory request as persisted metadata.
        let paths = ["/opt/homebrew/bin/ffmpeg", "/usr/local/bin/ffmpeg", "/usr/bin/ffmpeg"]
        guard let executable = paths.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else {
            throw AutomationServiceError.message("La saisie manuelle nécessite ffmpeg pour écrire les tags MP4 (brew install ffmpeg). MP4 conservé localement ; transfert refusé.")
        }
        let staged = output.deletingLastPathComponent().appendingPathComponent("manual-\(UUID().uuidString).mp4")
        defer { try? FileManager.default.removeItem(at: staged) }
        do {
            _ = try await ProcessWorker.run(executable: URL(fileURLWithPath: executable), arguments: [
                "-v", "error", "-nostdin", "-n", "-i", output.path,
                "-map", "0", "-c", "copy", "-map_metadata", "0", "-map_chapters", "0",
                "-metadata", "title=\(metadata.title)", "-metadata", "date=\(metadata.year)",
                "-f", "mp4", staged.path
            ], timeout: 24 * 60 * 60)
        } catch is CancellationError { throw CancellationError() }
        catch { throw AutomationServiceError.message("Écriture des tags manuels impossible : \(error.localizedDescription). MP4 initial conservé ; transfert refusé.") }
        try Task.checkCancellation()
        _ = try await MediaValidationService.validate(source: source, output: staged, expected: metadata)
        _ = try await GeneratedOutput.verify(url: output, source: source, root: root, jobID: jobID, expectedDigest: originalDigest)
        try Task.checkCancellation()
        _ = try FileManager.default.replaceItemAt(output, withItemAt: staged)
        _ = try await MediaValidationService.validate(source: source, output: output, expected: metadata)
    }
}
