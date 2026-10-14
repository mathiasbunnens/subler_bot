import Foundation

public struct FileStabilityTracker {
    private struct Snapshot { var size: Int64; var modified: Date; var since: Date }
    private var snapshots: [String: Snapshot] = [:]
    public init() {}
    public mutating func reset(path: String) { snapshots.removeValue(forKey: path) }
    public mutating func observe(path: String, size: Int64, modified: Date, now: Date, quietPeriod: TimeInterval = 10) -> Bool {
        guard size > 0 else { snapshots.removeValue(forKey: path); return false }
        if let previous = snapshots[path], previous.size == size, previous.modified == modified {
            return now.timeIntervalSince(previous.since) >= quietPeriod && now.timeIntervalSince(modified) >= quietPeriod
        }
        snapshots[path] = Snapshot(size: size, modified: modified, since: now)
        return false
    }
}

public enum FileIdentity {
    public static func fingerprint(_ url: URL) throws -> String {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        guard attributes[.type] as? FileAttributeType == .typeRegular,
              let size = attributes[.size] as? NSNumber,
              let modified = attributes[.modificationDate] as? Date else {
            throw CocoaError(.fileReadUnsupportedScheme)
        }
        return "\(url.standardizedFileURL.resolvingSymlinksInPath().path)|\(attributes[.systemFileNumber] ?? "")|\(size)|\(modified.timeIntervalSince1970)"
    }
}
