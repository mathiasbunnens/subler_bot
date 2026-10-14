import Foundation

/// The watched folder, the conversion cache and the MKV sources stay on this Mac.
/// Only the validated MP4 goes to the server: reading sources or writing the
/// cache over SMB would send the film back and forth for nothing.
public enum LocalPathPolicy {
    /// True when the path (or its nearest existing parent) is on a local, non-/Volumes disk.
    public static func isOnThisMac(_ path: String) -> Bool {
        guard path.hasPrefix("/"), !path.contains("\0"), !path.split(separator: "/").contains("..") else { return false }
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
