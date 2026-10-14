import Foundation

/// Files received from the Finder "Envoyer au serveur" service. Only regular
/// .mkv files are accepted; they enter the normal queue, so conversion,
/// validation and the verified SMB transfer stay mandatory.
public enum FinderSubmission {
    public struct Result: Equatable, Sendable {
        public var accepted: [URL] = []
        public var rejected: [URL] = []
        /// Accepted MKV files on the server/another volume: advice only, not rejection.
        public var remote: [URL] = []
    }

    public static func partition(_ urls: [URL], isOnThisMac: (String) -> Bool = LocalPathPolicy.isOnThisMac) -> Result {
        var result = Result()
        var seen = Set<String>()
        for url in urls {
            let file = url.standardizedFileURL
            guard seen.insert(file.path).inserted else { continue }
            var isDirectory: ObjCBool = false
            let exists = FileManager.default.fileExists(atPath: file.path, isDirectory: &isDirectory)
            if file.isFileURL, exists, !isDirectory.boolValue, file.pathExtension.lowercased() == "mkv" {
                result.accepted.append(file)
                if !isOnThisMac(file.path) { result.remote.append(file) }
            } else {
                result.rejected.append(file)
            }
        }
        return result
    }

    /// Short French summary for the notification shown after a Finder submission.
    public static func summary(_ result: Result, added: Int) -> String {
        var parts: [String] = []
        if added > 0 { parts.append(added == 1 ? "1 film ajouté à la file" : "\(added) films ajoutés à la file") }
        let duplicates = result.accepted.count - added
        if duplicates > 0 { parts.append(duplicates == 1 ? "1 déjà dans la file" : "\(duplicates) déjà dans la file") }
        if !result.remote.isEmpty {
            let names = result.remote.prefix(3).map(\.lastPathComponent).joined(separator: ", ")
            parts.append("emplacement réseau ou externe : peut ralentir le traitement, stockage local conseillé — \(names)\(result.remote.count > 3 ? "…" : "")")
        }
        if !result.rejected.isEmpty {
            let names = result.rejected.prefix(3).map(\.lastPathComponent).joined(separator: ", ")
            parts.append("ignoré (MKV uniquement) : \(names)\(result.rejected.count > 3 ? "…" : "")")
        }
        return parts.isEmpty ? "Aucun fichier reçu." : parts.joined(separator: " · ")
    }
}
