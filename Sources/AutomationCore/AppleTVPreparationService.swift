import Foundation
import AVFoundation
import Darwin

public struct AppleTVTools: Sendable {
    public let ffmpeg: URL
    public let ffprobe: URL
    public init(ffmpeg: URL, ffprobe: URL) { self.ffmpeg = ffmpeg; self.ffprobe = ffprobe }
    public static func discover() throws -> Self {
        // GUI launches do not inherit the interactive shell PATH. Never download binaries at runtime.
        for root in ["/opt/homebrew/bin", "/usr/local/bin"] {
            let base = URL(fileURLWithPath: root)
            let tools = Self(ffmpeg: base.appendingPathComponent("ffmpeg"), ffprobe: base.appendingPathComponent("ffprobe"))
            if [tools.ffmpeg, tools.ffprobe].allSatisfy({ FileManager.default.isExecutableFile(atPath: $0.path) }) { return tools }
        }
        throw AutomationServiceError.message("FFmpeg et ffprobe requis : installer avec brew install ffmpeg, puis réessayer. Aucun codec n’est installé dans Subler.")
    }
}

private final class PreparationCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false
    func cancel() { lock.lock(); value = true; lock.unlock() }
    var cancelled: Bool { lock.lock(); defer { lock.unlock() }; return value }
}

/// Only owns direct FFmpeg/ffprobe children; no Apple Events, shell, or shared Subler queue.
internal enum PreparationProcess {
    static func run(_ executable: URL, _ arguments: [String], timeout: TimeInterval,
                    capture: Bool = false, tick: @escaping @Sendable (String) throws -> Void = { _ in }) async throws -> Data {
        let cancellation = PreparationCancellation()
        return try await withTaskCancellationHandler(operation: {
            try await withCheckedThrowingContinuation { continuation in
                DispatchQueue.global(qos: .userInitiated).async {
                    do {
                        if cancellation.cancelled { throw CancellationError() }
                        let pipe = Pipe()
                        let process = Process()
                        process.executableURL = executable
                        process.arguments = arguments
                        process.standardInput = FileHandle.nullDevice
                        process.standardOutput = pipe
                        // FFmpeg error text can contain personal paths/tags. Do not persist or display it.
                        process.standardError = FileHandle.nullDevice
                        let fd = pipe.fileHandleForReading.fileDescriptor
                        _ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK)
                        try process.run()
                        try? pipe.fileHandleForWriting.close()
                        defer {
                            if process.isRunning {
                                process.terminate()
                                let grace = Date().addingTimeInterval(1)
                                while process.isRunning && Date() < grace { Thread.sleep(forTimeInterval: 0.01) }
                                if process.isRunning { kill(process.processIdentifier, SIGKILL) }
                            }
                            process.waitUntilExit()
                            try? pipe.fileHandleForReading.close()
                        }
                        let deadline = Date().addingTimeInterval(timeout)
                        var data = Data(), pending = ""
                        var buffer = [UInt8](repeating: 0, count: 8192)
                        repeat {
                            // Snapshot before draining so an exit racing the read cannot discard final JSON.
                            let running = process.isRunning
                            if cancellation.cancelled { throw CancellationError() }
                            guard Date() < deadline else { throw AutomationServiceError.message("Délai de préparation dépassé ; seul le processus de cette tâche est arrêté.") }
                            while true {
                                let count = Darwin.read(fd, &buffer, buffer.count)
                                if count <= 0 { break }
                                if capture {
                                    guard data.count + count <= 1024 * 1024 else { throw AutomationServiceError.message("Diagnostic trop volumineux (limite 1 Mio).") }
                                    data.append(contentsOf: buffer.prefix(count))
                                } else {
                                    pending += String(decoding: buffer.prefix(count), as: UTF8.self)
                                    guard pending.utf8.count <= 65536 else { throw AutomationServiceError.message("Progression invalide.") }
                                    while let end = pending.firstIndex(of: "\n") {
                                        let line = String(pending[..<end]); pending.removeSubrange(...end)
                                        try tick(line)
                                    }
                                }
                            }
                            try tick("")
                            if !running { break }
                            Thread.sleep(forTimeInterval: 0.05)
                        } while true
                        process.waitUntilExit()
                        guard process.terminationStatus == 0 else {
                            throw AutomationServiceError.message("\(executable.lastPathComponent) a échoué (code \(process.terminationStatus)). Codec, accélération matérielle ou conteneur non pris en charge ; aucun résultat publié.")
                        }
                        if cancellation.cancelled { throw CancellationError() }
                        continuation.resume(returning: data)
                    } catch { continuation.resume(throwing: error) }
                }
            }
        }, onCancel: { cancellation.cancel() })
    }
}

internal struct PreparationIdentity: Equatable, Sendable {
    let device: Int32
    let inode: UInt64
    let size: Int64
    let seconds: Int
    let nanos: Int
    static func read(_ url: URL, directory: Bool = false) throws -> Self {
        var info = stat()
        guard url.isFileURL, lstat(url.path, &info) == 0,
              (info.st_mode & S_IFMT) == (directory ? S_IFDIR : S_IFREG) else {
            throw AutomationServiceError.message("Fichier/dossier absent, lien symbolique ou type non autorisé.")
        }
        return Self(device: info.st_dev, inode: info.st_ino, size: info.st_size,
                    seconds: info.st_mtimespec.tv_sec, nanos: info.st_mtimespec.tv_nsec)
    }
    func sameNode(as other: Self) -> Bool { device == other.device && inode == other.inode }
}

public enum AppleTVPreparationService {
    public static let maximumTemporaryBytes: Int64 = 64 * 1024 * 1024 * 1024

    public static func inspect(source: URL, tools: AppleTVTools? = nil) async throws -> AppleTVMedia {
        _ = try PreparationIdentity.read(source)
        let tools = try tools ?? .discover()
        let entries = "stream=index,codec_type,codec_name,codec_tag_string,profile,pix_fmt,level,width,height,avg_frame_rate,sample_aspect_ratio,color_transfer,color_primaries,color_space,color_range,channels,sample_rate:stream_disposition=attached_pic:stream_side_data:format=duration"
        let data = try await PreparationProcess.run(tools.ffprobe, ["-v", "error", "-show_entries", entries, "-of", "json", source.path], timeout: 60, capture: true)
        do {
            let media = try AppleTVMedia.decode(data)
            guard let video = media.videos.first, video.hdr || video.dolbyVision else { return media }
            // Matroska often exposes mastering/CLL only on decoded frames, not streams.
            // Bound decoding to the first packet; never scan an entire user's movie.
            let frameData = try await PreparationProcess.run(tools.ffprobe,
                ["-v", "error", "-select_streams", String(video.index), "-read_intervals", "%+#1",
                 "-show_frames", "-show_entries", "frame=stream_index:frame_side_data", "-of", "json", source.path], timeout: 60, capture: true)
            let frames = (try JSONSerialization.jsonObject(with: frameData) as? [String: Any])?["frames"] as? [[String: Any]] ?? []
            var json = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
            var streams = json["streams"] as? [[String: Any]] ?? []
            if let index = streams.firstIndex(where: { $0["index"] as? Int == video.index }) {
                var side = streams[index]["side_data_list"] as? [[String: Any]] ?? []
                for entry in frames.first?["side_data_list"] as? [[String: Any]] ?? [] {
                    if !side.contains(where: { $0["side_data_type"] as? String == entry["side_data_type"] as? String }) { side.append(entry) }
                }
                streams[index]["side_data_list"] = side
            }
            json["streams"] = streams
            return try AppleTVMedia.decode(JSONSerialization.data(withJSONObject: json))
        }
        catch is CancellationError { throw CancellationError() }
        catch { throw AutomationServiceError.message("Diagnostic ffprobe illisible ; préparation refusée.") }
    }

    /// Restart always reprobes/restarts; no incomplete cache is ever accepted as a finished movie.
    public static func prepare(source: URL, destination: URL, mode: AppleTVMode,
                               allowTrackLoss: Bool = false, allowDynamicHDRLoss: Bool = false, tools: AppleTVTools? = nil,
                               maximumBytes: Int64 = maximumTemporaryBytes,
                               progress: @escaping @Sendable (Double) -> Void = { _ in }) async throws -> URL {
        try Task.checkCancellation()
        let original = try PreparationIdentity.read(source)
        let parent = destination.deletingLastPathComponent().resolvingSymlinksInPath()
        guard destination.isFileURL, destination.pathExtension.lowercased() == "mp4",
              destination.standardizedFileURL == parent.appendingPathComponent(destination.lastPathComponent).standardizedFileURL,
              source.resolvingSymlinksInPath() != destination.standardizedFileURL else {
            throw AutomationServiceError.message("Destination MP4 locale distincte requise.")
        }
        var existing = stat()
        guard lstat(destination.path, &existing) != 0, errno == ENOENT else {
            throw AutomationServiceError.message("La destination existe déjà : aucun remplacement autorisé.")
        }
        let parentID = try PreparationIdentity.read(parent, directory: true)
        guard try parent.resourceValues(forKeys: [.volumeIsLocalKey]).volumeIsLocal == true else {
            throw AutomationServiceError.message("Préparer d’abord sur un disque local, puis copier le MP4 sur le serveur.")
        }
        let tools = try tools ?? .discover()
        let media = try await inspect(source: source, tools: tools)
        let plan = try AppleTVPlan.make(media: media, mode: mode, allowTrackLoss: allowTrackLoss, allowDynamicHDRLoss: allowDynamicHDRLoss)
        guard try PreparationIdentity.read(source) == original else { throw AutomationServiceError.message("La source a changé depuis l’analyse.") }
        let scratch = parent.appendingPathComponent(".appletv-" + UUID().uuidString, isDirectory: true)
        guard mkdir(scratch.path, 0o700) == 0 else { throw AutomationServiceError.message("Impossible de créer le cache exclusif.") }
        let owned = try PreparationIdentity.read(scratch, directory: true)
        defer {
            // Never follow a replaced directory, and never clean another task's cache.
            if let now = try? PreparationIdentity.read(scratch, directory: true), owned.sameNode(as: now),
               let currentParent = try? PreparationIdentity.read(parent, directory: true), parentID.sameNode(as: currentParent) {
                try? FileManager.default.removeItem(at: scratch)
            }
        }
        let output = scratch.appendingPathComponent("prepared.mp4")
        let free = try FileManager.default.attributesOfFileSystem(forPath: parent.path)[.systemFreeSize] as? NSNumber
        guard let free, free.int64Value > 1024 * 1024 * 1024 else { throw AutomationServiceError.message("Moins de 1 Gio libre : préparation refusée.") }
        guard maximumBytes > 0 else { throw AutomationServiceError.message("Budget temporaire invalide.") }
        let budget = min(maximumTemporaryBytes, maximumBytes, free.int64Value - 512 * 1024 * 1024)
        let args = plan.arguments(source: source, output: output)
        // Do not use -fs: FFmpeg may return success after truncating the end. Enforce a
        // monitored budget instead; overshoot is limited to one 50 ms write burst.
        _ = try await PreparationProcess.run(tools.ffmpeg, args, timeout: 24 * 3600) { line in
            guard let now = try? PreparationIdentity.read(scratch, directory: true), owned.sameNode(as: now) else {
                throw AutomationServiceError.message("Le cache a changé de propriétaire.")
            }
            if let attrs = try? FileManager.default.attributesOfItem(atPath: output.path),
               let size = attrs[.size] as? NSNumber, size.int64Value >= budget {
                throw AutomationServiceError.message("Limite de cache atteinte.")
            }
            if line.hasPrefix("out_time_us="), let value = Double(line.dropFirst(12)) {
                progress(min(0.95, max(0, value / 1_000_000 / media.duration * 0.95)))
            }
        }
        let finished = try await inspect(source: output, tools: tools)
        guard finished.videos.count == 1, finished.audios.count == media.audios.count,
              finished.duration.isFinite, abs(finished.duration - media.duration) <= max(0.5, media.duration * 0.01) else {
            throw AutomationServiceError.message("Durée ou pistes du résultat invalides : publication bloquée.")
        }
        // Reject outputs that drifted outside the selected conservative Apple TV profile.
        _ = try AppleTVPlan.make(media: finished, mode: .preserve, allowTrackLoss: true)
        if mode == .hdr10 { try AppleTVPlan.validateHDR10Output(source: media, output: finished) }
        if media.videos[0].hdr {
            guard finished.videos[0].hdr else { throw AutomationServiceError.message("Signal HDR perdu : publication bloquée.") }
        }
        progress(0.97)
        try await verifyDecodableImage(output)
        try Task.checkCancellation()
        guard try PreparationIdentity.read(source) == original,
              owned.sameNode(as: try PreparationIdentity.read(scratch, directory: true)),
              parentID.sameNode(as: try PreparationIdentity.read(parent, directory: true)) else {
            throw AutomationServiceError.message("Source ou dossier modifié pendant la préparation : résultat non publié.")
        }
        let outputID = try PreparationIdentity.read(output)
        // Atomic no-replace publication on the same volume, including a concurrent destination race.
        guard link(output.path, destination.path) == 0 else { throw AutomationServiceError.message("Publication exclusive impossible : destination existante ou disque incompatible.") }
        guard let published = try? PreparationIdentity.read(destination), outputID == published else {
            throw AutomationServiceError.message("Identité du résultat publié non confirmée.")
        }
        progress(1)
        return destination
    }

    public static func verifyDecodableImage(_ url: URL) async throws {
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 640, height: 360)
        let timeout = DispatchWorkItem {
            asset.cancelLoading()
            generator.cancelAllCGImageGeneration()
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + 30, execute: timeout)
        defer { timeout.cancel() }
        try await withTaskCancellationHandler(operation: {
            do {
                try Task.checkCancellation()
                let tracks = try await asset.loadTracks(withMediaType: .video)
                guard tracks.count == 1 else { throw AutomationServiceError.message("Aucune piste vidéo native exploitable.") }
                let duration = try await asset.load(.duration).seconds
                for seconds in [0.0, max(0, duration / 2), max(0, duration - 0.1)] {
                    try Task.checkCancellation()
                    let image = try await generator.image(at: CMTime(seconds: seconds, preferredTimescale: 600)).image
                    guard image.width > 0, image.height > 0 else { throw AutomationServiceError.message("Image vide.") }
                }
                try Task.checkCancellation()
            } catch {
                try Task.checkCancellation()
                throw AutomationServiceError.message("QuickTime/AVFoundation ne décode pas l’image du MP4 (ou délai de 30 s dépassé) : aucun résultat publié.")
            }
        }, onCancel: {
            asset.cancelLoading()
            generator.cancelAllCGImageGeneration()
        })
    }
}
