import Foundation
import AutomationCore

struct AppSettings: Codable, Equatable {
    var sourcePath = NSHomeDirectory() + "/Movies/Subler Automation/À convertir"
    var temporaryPath = NSHomeDirectory() + "/Movies/Subler Automation/Temp"
    var smb = SMBConfiguration()
    var watchFolder = true
    var notifications = true
    var cleanupTemporary = false
    var paused = false
    static var file: URL {
        if let testRoot = ProcessInfo.processInfo.environment["SUBLER_AUTOMATION_TEST_ROOT"] {
            return URL(fileURLWithPath: testRoot).appendingPathComponent("settings.json")
        }
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Subler Automation/settings.json")
    }
    static func load() throws -> Self {
        guard FileManager.default.fileExists(atPath: file.path) else {
            var defaults = Self()
            if let testRoot = ProcessInfo.processInfo.environment["SUBLER_AUTOMATION_TEST_ROOT"] {
                defaults.sourcePath = testRoot + "/Source"; defaults.temporaryPath = testRoot + "/Temp"
                defaults.notifications = false
            }
            return defaults
        }
        return try JSONDecoder().decode(Self.self, from: Data(contentsOf: file))
    }
    func save() throws {
        try FileManager.default.createDirectory(at: Self.file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(self).write(to: Self.file, options: .atomic)
    }
}
