import Foundation
import AutomationCore

enum AppPresentationMode: String, Codable, CaseIterable {
    case menuBar, normal
}

struct AppSettings: Codable, Equatable {
    var sourcePath = NSHomeDirectory() + "/Movies/Subler Automation/À convertir"
    var temporaryPath = NSHomeDirectory() + "/Movies/Subler Automation/Temp"
    var smb = SMBConfiguration()
    var watchFolder = true
    var notifications = true
    var cleanupTemporary = false
    var paused = false
    var presentationMode: AppPresentationMode = .menuBar

    init() {}
    func differsForEditing(from saved: Self) -> Bool {
        var editable = self
        editable.paused = saved.paused
        return editable != saved
    }

    private enum CodingKeys: String, CodingKey {
        case sourcePath, temporaryPath, smb, watchFolder, notifications, cleanupTemporary, paused, presentationMode
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        sourcePath = try values.decode(String.self, forKey: .sourcePath)
        temporaryPath = try values.decode(String.self, forKey: .temporaryPath)
        smb = try values.decode(SMBConfiguration.self, forKey: .smb)
        watchFolder = try values.decode(Bool.self, forKey: .watchFolder)
        notifications = try values.decode(Bool.self, forKey: .notifications)
        cleanupTemporary = try values.decode(Bool.self, forKey: .cleanupTemporary)
        paused = try values.decode(Bool.self, forKey: .paused)
        // Only the new field is optional: malformed existing data still fails safely.
        presentationMode = try values.decodeIfPresent(AppPresentationMode.self, forKey: .presentationMode) ?? .menuBar
    }
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
