import Foundation

public final class QueueStore {
    public let root: URL
    public init(root: URL) throws { self.root = root; try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true) }
    public func load() throws -> [MovieJob] {
        let file = root.appendingPathComponent("jobs.json")
        guard FileManager.default.fileExists(atPath: file.path) else { return [] }
        return try JSONDecoder().decode([MovieJob].self, from: Data(contentsOf: file))
    }
    public func save(_ jobs: [MovieJob]) throws {
        var seen = Set<UUID>()
        let unique = jobs.filter { seen.insert($0.id).inserted }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(unique).write(to: root.appendingPathComponent("jobs.json"), options: .atomic)
    }
    public func log(_ text: String) {
        let line = "\(ISO8601DateFormatter().string(from: Date())) \(text)\n"
        let file = root.appendingPathComponent("automation.log")
        if !FileManager.default.fileExists(atPath: file.path) { FileManager.default.createFile(atPath: file.path, contents: nil) }
        guard let handle = try? FileHandle(forWritingTo: file) else { return }
        defer { try? handle.close() }
        _ = try? handle.seekToEnd(); try? handle.write(contentsOf: Data(line.utf8))
    }
}
