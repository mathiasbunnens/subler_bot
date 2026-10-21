import AppKit
import CoreGraphics
import CryptoKit

// Read-only observation of the isolated local build while a supplied test runs.
// No Accessibility permissions, window movement, app activation or screenshots.
let queue = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Subler/queue.sbqueue")
func queueDigest() throws -> Data? {
    guard FileManager.default.fileExists(atPath: queue.path) else { return nil }
    return Data(SHA256.hash(data: try Data(contentsOf: queue)))
}
let before = try queueDigest()
let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
process.arguments = Array(CommandLine.arguments.dropFirst())
try process.run()
var samples = 0, windows = 0, active = 0
var observed = Set<pid_t>()
let expectedEngine = ProcessInfo.processInfo.environment["SUBLER_EXPECTED_ENGINE"].map { URL(fileURLWithPath: $0).standardizedFileURL.resolvingSymlinksInPath() }
repeat {
    let local = NSRunningApplication.runningApplications(withBundleIdentifier: "local.sublerautomation.Subler")
    let pids = Set(local.map { $0.processIdentifier })
    for app in local where observed.insert(app.processIdentifier).inserted {
        guard let actual = app.bundleURL?.standardizedFileURL.resolvingSymlinksInPath() else { exit(1) }
        print("OBSERVED_ENGINE pid=\(app.processIdentifier) url=\(actual.path)")
        if let expectedEngine {
            guard actual == expectedEngine else { exit(1) }
        }
    }
    if let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier, pids.contains(pid) { active += 1 }
    let listed = CGWindowListCopyWindowInfo(.optionAll, kCGNullWindowID) as? [[String: Any]] ?? []
    windows += listed.filter { entry in
        guard let pid = entry[kCGWindowOwnerPID as String] as? Int32 else { return false }
        return pids.contains(pid)
    }.count
    samples += 1
    Thread.sleep(forTimeInterval: 0.02)
} while process.isRunning
process.waitUntilExit()
let unchanged = try before == queueDigest()
print("EXTERNAL_LOCAL_OBSERVATION samples=\(samples) windows=\(windows) localFrontmost=\(active) installedQueueUnchanged=\(unchanged)")
guard windows == 0, active == 0, unchanged, process.terminationStatus == 0,
      expectedEngine == nil || !observed.isEmpty else { exit(1) }
