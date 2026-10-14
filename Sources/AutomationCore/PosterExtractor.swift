import AVFoundation
import Foundation

/// Extracts the cover artwork that Subler embedded in the generated MP4 so the
/// interface can show the film currently sent to the server. The poster is a
/// local copy inside the job's own work folder, never a remote URL.
public enum PosterExtractor {
    public static let fileName = "poster"

    /// Returns the written poster, or nil when the MP4 has no artwork.
    public static func extract(from output: URL, jobFolder: URL) async -> URL? {
        let asset = AVURLAsset(url: output)
        guard let metadata = try? await asset.load(.metadata) else { return nil }
        let artwork = AVMetadataItem.metadataItems(from: metadata, filteredByIdentifier: .commonIdentifierArtwork)
        for item in artwork {
            guard let data = try? await item.load(.dataValue), !data.isEmpty,
                  let ext = imageExtension(data) else { continue }
            let destination = jobFolder.appendingPathComponent("\(fileName).\(ext)")
            do {
                try FileManager.default.createDirectory(at: jobFolder, withIntermediateDirectories: true)
                try data.write(to: destination, options: .atomic)
                return destination
            } catch { return nil }
        }
        return nil
    }

    /// Only JPEG and PNG cover atoms are accepted.
    static func imageExtension(_ data: Data) -> String? {
        let bytes = [UInt8](data.prefix(8))
        if bytes.starts(with: [0xFF, 0xD8, 0xFF]) { return "jpg" }
        if bytes.starts(with: [0x89, 0x50, 0x4E, 0x47]) { return "png" }
        return nil
    }

    /// A poster path is shown only if it lies inside this job's own folder.
    public static func isOwned(_ path: String, workRoot: String?, jobID: UUID) -> Bool {
        guard let workRoot else { return false }
        let folder = URL(fileURLWithPath: workRoot).appendingPathComponent(jobID.uuidString).standardizedFileURL.path + "/"
        return URL(fileURLWithPath: path).standardizedFileURL.path.hasPrefix(folder)
    }
}
