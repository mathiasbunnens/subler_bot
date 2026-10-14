import Foundation
import CryptoKit
import AutomationCore

// Compile with the real app models/services, not a simulated queue.
@main
struct PipelineSmoke {
    @MainActor static func main() async {
        var generatedRemote: URL?
        do {
            guard ProcessInfo.processInfo.environment["SUBLER_AUTOMATION_TEST_ROOT"] != nil else { throw UserFacingError("An isolated test root is mandatory.") }
            let server = SMBService(), configuration = SMBConfiguration.firstLaunchDefault()
            let mount = try await server.mountedShare(configuration: configuration)
            let expectedDirectory = mount.root.appendingPathComponent("Amélie (2001)")
            guard !FileManager.default.fileExists(atPath: expectedDirectory.path) else {
                throw UserFacingError("A film folder already exists at the synthetic fixture's final name. No full-pipeline test will touch it.")
            }
            let root = AppSettings.file.deletingLastPathComponent()
            var settings = try AppSettings.load()
            settings.paused = false; settings.notifications = false; settings.cleanupTemporary = false
            try settings.save()
            try FileManager.default.createDirectory(atPath: settings.sourcePath, withIntermediateDirectories: true)
            let fixture = URL(fileURLWithPath: "/Users/mathiasbunnens/.hermes/cache/scratch/subler-automation-integration/Amelie.2001.mkv")
            let source = URL(fileURLWithPath: settings.sourcePath).appendingPathComponent("Amelie.2001.mkv")
            try FileManager.default.copyItem(at: fixture, to: source)
            let originalHash = SHA256.hash(data: try Data(contentsOf: source))
            let queue = JobQueueService()
            let deadline = Date().addingTimeInterval(180)
            while Date() < deadline {
                await queue.tick()
                if let value = queue.jobs.first, value.status == .completed {
                    guard let remotePath = value.destinationPath, let localPath = value.localPath, let digest = value.validatedDigest else { throw UserFacingError("Completed job lacks output evidence.") }
                    let remote = URL(fileURLWithPath: remotePath)
                    generatedRemote = remote
                    let actual = SHA256.hash(data: try Data(contentsOf: remote)).map { String(format: "%02x", $0) }.joined()
                    guard actual == digest, try SHA256.hash(data: Data(contentsOf: source)) == originalHash,
                          remote.path == expectedDirectory.appendingPathComponent("Amélie (2001).mp4").path,
                          FileManager.default.fileExists(atPath: localPath) else { throw UserFacingError("Pipeline output verification failed.") }
                    let disk = try QueueStore(root: root).load()
                    guard disk.count == 1, disk[0].status == .completed else { throw UserFacingError("Completion was not persisted.") }
                    print("PIPELINE_PASS: watched MKV -> native Subler -> verified metadata/tracks/duration -> named SMB folder -> hashed remote MP4 -> persisted completed; source unchanged")
                    print("Isolated queue: \(root.path)")
                    let current = try await server.mountedShare(configuration: configuration)
                    guard current.root == mount.root, current.origin == mount.origin,
                          try FileManager.default.contentsOfDirectory(atPath: expectedDirectory.path) == [remote.lastPathComponent],
                          SHA256.hash(data: try Data(contentsOf: remote)).map({ String(format: "%02x", $0) }).joined() == digest else {
                        throw UserFacingError("Refusing cleanup of changed test destination.")
                    }
                    try FileManager.default.removeItem(at: remote)
                    try FileManager.default.removeItem(at: expectedDirectory)
                    generatedRemote = nil
                    print("Synthetic server fixture cleaned; no existing movie touched.")
                    return
                }
                if let value = queue.jobs.first, [.failed, .paused].contains(value.status) {
                    throw UserFacingError("Pipeline stopped: \(value.error ?? value.status.rawValue)")
                }
                try await Task.sleep(nanoseconds: 1_000_000_000)
            }
            throw UserFacingError("Pipeline deadline exceeded (including 60s stability wait).")
        } catch {
            print("PIPELINE_FAIL: \(error.localizedDescription)")
            if let generatedRemote { print("Generated test output retained: \(generatedRemote.path)") }
            exit(1)
        }
    }
}
