import Foundation

public final class QueueStore {
    public let root: URL
    private let stateWriter: (Data, URL) throws -> Void
    public convenience init(root: URL) throws {
        try self.init(root: root, stateWriter: { try $0.write(to: $1, options: .atomic) })
    }
    // Internal fixture seam: production always uses the atomic filesystem writer above.
    internal init(root: URL, stateWriter: @escaping (Data, URL) throws -> Void) throws {
        self.root = root; self.stateWriter = stateWriter
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }
    private struct State: Codable {
        var version = 1
        var jobs: [MovieJob]
        var dismissedFingerprints: Set<String> = []
    }
    private var file: URL { root.appendingPathComponent("jobs.json") }
    private func loadState() throws -> State {
        guard FileManager.default.fileExists(atPath: file.path) else { return State(jobs: []) }
        let data = try Data(contentsOf: file)
        // Preserve the existing array format on read; migrate only on a successful atomic write.
        if let legacy = try? JSONDecoder().decode([MovieJob].self, from: data) { return State(jobs: legacy) }
        let state = try JSONDecoder().decode(State.self, from: data)
        guard state.version == 1 else { throw InterventionRemovalError.unsupportedStore }
        return state
    }
    public func load() throws -> [MovieJob] { try loadState().jobs }
    public func isDismissed(fingerprint: String) throws -> Bool {
        try loadState().dismissedFingerprints.contains(fingerprint)
    }
    public func save(_ jobs: [MovieJob], explicitlyAddedFingerprints: Set<String> = []) throws {
        var state = try loadState()
        state.jobs = jobs
        state.dismissedFingerprints.subtract(explicitlyAddedFingerprints)
        try saveState(state)
    }
    private func saveState(_ state: State) throws {
        var state = state
        var seen = Set<UUID>()
        state.jobs = state.jobs.filter { seen.insert($0.id).inserted }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(state)
        try stateWriter(data, file)
        guard try Data(contentsOf: file) == data else { throw InterventionRemovalError.failedReadback }
        _ = try loadState()
    }
    /// Queue removal and watched-source suppression share one atomic persistence boundary.
    public func removeIntervention(_ id: UUID, jobs: [MovieJob], activeID: UUID?) throws -> [MovieJob] {
        let job = try InterventionRemovalPolicy.validate(id, jobs: jobs, activeID: activeID)
        let source = URL(fileURLWithPath: job.sourcePath)
        let fingerprint: String
        do { fingerprint = try FileIdentity.fingerprint(source) }
        catch CocoaError.fileReadNoSuchFile { fingerprint = job.fingerprint }
        catch { throw error }
        var state = try loadState()
        state.jobs = jobs.filter { $0.id != id }
        state.dismissedFingerprints.insert(fingerprint)
        try saveState(state)
        return state.jobs
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
