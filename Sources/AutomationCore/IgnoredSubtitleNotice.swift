import Foundation

/// A source subtitle track the embedded engine cannot convert in the background (bitmap PGS needs the UI's OCR).
/// It is skipped, never the whole film; video/audio are never skipped silently (see MediaValidationService).
public enum IgnoredSubtitleNotice {
    /// ffprobe codec names the engine converts (tx3g) or copies. Anything else is skipped by the engine.
    static let handledCodecs: Set<String> = ["subrip", "srt", "ass", "ssa", "text", "mov_text", "webvtt", "dvd_subtitle"]

    struct Stream: Decodable { let codec_name: String?; let tags: [String: String]? }
    struct Probe: Decodable { let streams: [Stream] }

    public static func messages(fromProbeJSON json: String) -> [String] {
        guard let probe = try? JSONDecoder().decode(Probe.self, from: Data(json.utf8)) else { return [] }
        return probe.streams.compactMap { stream in
            guard let codec = stream.codec_name, !handledCodecs.contains(codec) else { return nil }
            let label = codec == "hdmv_pgs_subtitle" ? "PGS" : codec
            return "sous-titre \(label) \(stream.tags?["language"] ?? "und") ignoré (non convertible en arrière-plan)"
        }
    }

    /// Best effort and read-only: absent ffprobe or a probe failure yields no notice, never an error.
    public static func scan(source: URL) async -> [String] {
        let paths = ["/opt/homebrew/bin/ffprobe", "/usr/local/bin/ffprobe", "/usr/bin/ffprobe"]
        guard let path = paths.first(where: { FileManager.default.isExecutableFile(atPath: $0) }),
              let json = try? await ProcessWorker.run(executable: URL(fileURLWithPath: path),
                  arguments: ["-v", "error", "-select_streams", "s", "-show_entries", "stream=codec_name:stream_tags=language", "-of", "json", source.path],
                  timeout: 60) else { return [] }
        return messages(fromProbeJSON: json)
    }
}
