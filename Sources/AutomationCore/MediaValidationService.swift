import Foundation
import AVFoundation

public struct ValidatedMedia: Sendable {
    public let title: String
    public let year: Int
    public let size: Int64
    public init(title: String, year: Int, size: Int64) { self.title = title; self.year = year; self.size = size }
}

public enum MediaValidationService {
    public static func validate(source: URL, output: URL, expected: MetadataCandidate) async throws -> ValidatedMedia {
        let sourceAttributes = try? FileManager.default.attributesOfItem(atPath: source.path)
        let outputAttributes = try? FileManager.default.attributesOfItem(atPath: output.path)
        let sameInode = sourceAttributes?[.systemFileNumber] as? NSNumber != nil &&
            sourceAttributes?[.systemFileNumber] as? NSNumber == outputAttributes?[.systemFileNumber] as? NSNumber &&
            sourceAttributes?[.systemNumber] as? NSNumber == outputAttributes?[.systemNumber] as? NSNumber
        guard source.resolvingSymlinksInPath().standardizedFileURL != output.resolvingSymlinksInPath().standardizedFileURL && !sameInode else {
            throw AutomationServiceError.message("The source and output refer to the same file; the original is never a generated MP4.")
        }
        guard output.isFileURL, FileManager.default.isReadableFile(atPath: output.path),
              let size = try? output.resourceValues(forKeys: [.fileSizeKey]).fileSize, size > 0 else {
            throw AutomationServiceError.message("The output MP4 is missing, empty or unreadable: \(output.path)")
        }
        let handle = try FileHandle(forReadingFrom: output)
        defer { try? handle.close() }
        let header = try handle.read(upToCount: 32) ?? Data()
        guard header.count >= 12, String(decoding: header[4..<8], as: UTF8.self) == "ftyp",
              String(decoding: header[8..<12], as: UTF8.self) != "qt  " else {
            throw AutomationServiceError.message("The output is not an MP4 container.")
        }
        let asset = AVURLAsset(url: output)
        let duration = try await asset.load(.duration).seconds
        guard duration.isFinite && duration > 0 else { throw AutomationServiceError.message("The output has no readable positive duration.") }
        let outputVideo = try await asset.loadTracks(withMediaType: .video).count
        let outputAudio = try await asset.loadTracks(withMediaType: .audio).count
        let counts = try await sourceCounts(source)
        guard counts.duration.isFinite, counts.duration > 0,
              abs(duration - counts.duration) <= max(0.5, counts.duration * 0.01) else {
            throw AutomationServiceError.message("Output duration differs from the source: source=\(counts.duration)s, MP4=\(duration)s. Transfer blocked.")
        }
        guard counts.video > 0, outputVideo == counts.video, outputAudio >= counts.audio else {
            throw AutomationServiceError.message("Track validation failed: source has \(counts.video) video / \(counts.audio) audio; output has \(outputVideo) video / \(outputAudio) audio.")
        }
        // Read the actual iTunes MP4 atoms, not the filename or the requested metadata.
        let formats = try await asset.load(.availableMetadataFormats)
        var titles: [String] = []
        var dates: [String] = []
        for format in formats {
            let items = try await asset.loadMetadata(for: format)
            for item in items {
                if item.identifier == .iTunesMetadataSongName || item.commonKey == .commonKeyTitle {
                    if let text = try await item.load(.stringValue), !text.isEmpty { titles.append(text) }
                }
                if item.identifier == .iTunesMetadataReleaseDate {
                    if let text = try await item.load(.stringValue), !text.isEmpty { dates.append(text) }
                }
            }
        }
        let uniqueTitles = Set(titles)
        let years = Set(dates.compactMap { Int($0.prefix(4)) })
        guard uniqueTitles.count == 1, let title = uniqueTitles.first,
              MetadataMatching.normalized(title) == MetadataMatching.normalized(expected.title),
              years == Set([expected.year]) else {
            throw AutomationServiceError.message("Applied metadata does not match the selected candidate. Expected \(expected.title) (\(expected.year)); actual title tags: \(titles), release date tags: \(dates). Nothing should be transferred.")
        }
        return ValidatedMedia(title: title, year: expected.year, size: Int64(size))
    }

    private static func sourceCounts(_ source: URL) async throws -> (video: Int, audio: Int, duration: Double) {
        guard source.isFileURL, FileManager.default.isReadableFile(atPath: source.path) else {
            throw AutomationServiceError.message("The source is missing or unreadable: \(source.path)")
        }
        do {
            let asset = AVURLAsset(url: source)
            let video = try await asset.loadTracks(withMediaType: .video).count
            let audio = try await asset.loadTracks(withMediaType: .audio).count
            if video > 0 { return (video, audio, try await asset.load(.duration).seconds) }
        } catch { if error is CancellationError { throw error } }
        // AVFoundation cannot inspect Matroska. Require a real inspector rather than guessing counts.
        let paths = ["/opt/homebrew/bin/ffprobe", "/usr/local/bin/ffprobe", "/usr/bin/ffprobe"]
        guard let path = paths.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else {
            throw AutomationServiceError.message("AVFoundation cannot inspect this source container. Install ffprobe (brew install ffmpeg) to verify MKV video/audio preservation; validation is blocked without it.")
        }
        let json = try await ProcessWorker.run(executable: URL(fileURLWithPath: path), arguments: ["-v", "error", "-show_entries", "stream=codec_type:format=duration", "-of", "json", source.path], timeout: 60)
        struct Probe: Decodable {
            struct Stream: Decodable { let codec_type: String? }
            struct Format: Decodable { let duration: String? }
            let streams: [Stream]; let format: Format?
        }
        let probe = try JSONDecoder().decode(Probe.self, from: Data(json.utf8))
        return (probe.streams.filter { $0.codec_type == "video" }.count, probe.streams.filter { $0.codec_type == "audio" }.count, Double(probe.format?.duration ?? "") ?? 0)
    }
}
