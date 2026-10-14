import Foundation

/// Independent of job history: only a durable completion or an explicit reset changes it.
public final class CompletionCounterStore {
    private let file: URL
    private let writer: (Data, URL) throws -> Void
    private struct State: Codable { var completed: Int }

    public convenience init(root: URL) throws {
        try self.init(root: root, writer: { try $0.write(to: $1, options: .atomic) })
    }
    internal init(root: URL, writer: @escaping (Data, URL) throws -> Void) throws {
        file = root.appendingPathComponent("completion-counter.json")
        self.writer = writer
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }
    public func load() throws -> Int {
        guard FileManager.default.fileExists(atPath: file.path) else { return 0 }
        let value = try JSONDecoder().decode(State.self, from: Data(contentsOf: file)).completed
        guard value >= 0 else { throw CounterError.invalidValue }
        return value
    }
    @discardableResult public func recordCompletion() throws -> Int {
        let (next, overflow) = try load().addingReportingOverflow(1)
        guard !overflow else { throw CounterError.invalidValue }
        try save(next)
        return next
    }
    public func reset() throws {
        // Never replace a corrupt existing file, even on manual reset.
        _ = try load()
        try save(0)
    }
    private func save(_ value: Int) throws {
        let data = try JSONEncoder().encode(State(completed: value))
        try writer(data, file)
        guard try Data(contentsOf: file) == data else { throw CounterError.failedReadback }
    }
    private enum CounterError: LocalizedError {
        case invalidValue, failedReadback
        var errorDescription: String? {
            switch self {
            case .invalidValue: return "Compteur de films terminés invalide. Le fichier existant est conservé."
            case .failedReadback: return "Échec de vérification du compteur de films terminés."
            }
        }
    }
}
