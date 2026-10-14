import Foundation
import AutomationCore

@main struct PresentationSettingsTest {
    static func main() throws {
        let settings = AppSettings()
        precondition(!settings.differsForEditing(from: settings))
        var draft = settings
        draft.paused.toggle()
        precondition(!draft.differsForEditing(from: settings), "Operational pause is not a settings edit")
        draft.notifications.toggle()
        precondition(draft.differsForEditing(from: settings))
        draft.notifications = settings.notifications
        precondition(!draft.differsForEditing(from: settings), "Reverting edits hides Save")
        var legacy = try JSONSerialization.jsonObject(with: JSONEncoder().encode(settings)) as! [String: Any]
        legacy.removeValue(forKey: "presentationMode")
        legacy["sourcePath"] = "/legacy/source"
        legacy["temporaryPath"] = "/legacy/temp"
        legacy["paused"] = true
        legacy["notifications"] = false
        let legacyData = try JSONSerialization.data(withJSONObject: legacy)
        try FileManager.default.createDirectory(at: AppSettings.file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try legacyData.write(to: AppSettings.file)
        let decoded = try AppSettings.load()
        let unchangedLegacy = try Data(contentsOf: AppSettings.file)
        precondition(unchangedLegacy == legacyData, "Loading legacy settings must not rewrite the file")
        let encoded = try JSONSerialization.jsonObject(with: JSONEncoder().encode(decoded)) as! [String: Any]
        precondition(encoded["presentationMode"] as? String == "menuBar", "Legacy settings must default to menuBar")
        precondition(decoded.sourcePath == "/legacy/source" && decoded.temporaryPath == "/legacy/temp" && decoded.paused && !decoded.notifications)
        var withoutMode = encoded
        withoutMode.removeValue(forKey: "presentationMode")
        precondition(NSDictionary(dictionary: withoutMode).isEqual(to: legacy), "All legacy values must survive")
        var normal = encoded
        normal["presentationMode"] = "normal"
        let app = try JSONDecoder().decode(AppSettings.self, from: JSONSerialization.data(withJSONObject: normal))
        try app.save()
        let loaded = try AppSettings.load()
        precondition(loaded == app, "Normal mode must persist and roundtrip")
        let saved = try JSONSerialization.jsonObject(with: Data(contentsOf: AppSettings.file)) as! [String: Any]
        precondition(saved["presentationMode"] as? String == "normal")
        var unsupported = normal
        unsupported["presentationMode"] = "future-mode"
        let unsupportedData = try JSONSerialization.data(withJSONObject: unsupported)
        try unsupportedData.write(to: AppSettings.file)
        do {
            _ = try AppSettings.load()
            fatalError("Unknown presentation mode must not silently reset saved settings")
        } catch is DecodingError {}
        let unchangedUnsupported = try Data(contentsOf: AppSettings.file)
        precondition(unchangedUnsupported == unsupportedData)
        try app.save()
        print("PRESENTATION_SETTINGS_PASS: legacy file/value preservation, menuBar default, normal save/load, unknown-mode rejection without overwrite")
    }
}
