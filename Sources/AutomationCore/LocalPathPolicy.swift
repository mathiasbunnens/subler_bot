import Foundation

/// Local storage is recommended for performance, not required. Location advice
/// is separate from path validity, permissions and generated-file ownership.
public enum LocalPathPolicy {
    public static func isValidAbsolutePath(_ path: String) -> Bool {
        path.hasPrefix("/") && !path.contains("\0") && !path.split(separator: "/").contains("..")
    }

    /// Allows mounted network/external directories, but never creates a substitute mount.
    public static func directoryURL(_ path: String) throws -> URL {
        guard isValidAbsolutePath(path) else { throw CocoaError(.fileReadInvalidFileName) }
        let url = URL(fileURLWithPath: path).resolvingSymlinksInPath()
        if url.path == "/Volumes" || url.path.hasPrefix("/Volumes/") {
            var existing = url
            while !FileManager.default.fileExists(atPath: existing.path), existing.path != "/" { existing.deleteLastPathComponent() }
            guard let volume = try existing.resourceValues(forKeys: [.volumeURLKey]).volume,
                  volume.path.hasPrefix("/Volumes/") else { throw CocoaError(.fileNoSuchFile) }
        }
        return url
    }

    public static func performanceWarning(_ path: String) -> String? {
        guard isValidAbsolutePath(path), !isOnThisMac(path) else { return nil }
        return "Un dossier sur le serveur peut ralentir le traitement (lectures et écritures réseau supplémentaires). Un stockage local est conseillé, mais cet emplacement reste autorisé s’il est accessible."
    }

    /// True when the path (or its nearest existing parent) is on a local, non-/Volumes disk.
    public static func isOnThisMac(_ path: String) -> Bool {
        guard isValidAbsolutePath(path) else { return false }
        // Resolve symlinks on the nearest existing ancestor: a link to /Volumes must not pass.
        var existing = URL(fileURLWithPath: path)
        while !FileManager.default.fileExists(atPath: existing.path), existing.path != "/" { existing.deleteLastPathComponent() }
        existing = existing.resolvingSymlinksInPath()
        guard !existing.path.hasPrefix("/Volumes/"), !URL(fileURLWithPath: path).resolvingSymlinksInPath().path.hasPrefix("/Volumes/"),
              let values = try? existing.resourceValues(forKeys: [.volumeIsLocalKey]) else { return false }
        return values.volumeIsLocal == true
    }

    /// Server path of a published film: `<share>/<Name>/<Name>.mp4`.
    public static func publishedMovie(shareRoot: URL, movieName: String) -> URL {
        shareRoot.appendingPathComponent(movieName).appendingPathComponent(movieName + ".mp4")
    }
}
