import Foundation

public enum AutomationServiceError: LocalizedError, Sendable {
    case message(String)
    public var errorDescription: String? { if case let .message(text) = self { return text }; return nil }
}

/// Runs Apple Events out of process and never blocks the main actor.
public enum AppleScriptService {
    public static func run(_ script: String, timeout: TimeInterval = 180) async throws -> String {
        try await ProcessWorker.run(executable: URL(fileURLWithPath: "/usr/bin/osascript"),
                                    arguments: ["-e", script], timeout: timeout)
    }

    public static func literal(_ value: String) -> String {
        "\"" + value.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }
}

private final class ProcessCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    func cancel() { lock.lock(); cancelled = true; lock.unlock() }
    var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return cancelled }
}

internal enum ProcessWorker {
    static func run(executable: URL, arguments: [String], timeout: TimeInterval) async throws -> String {
        let cancellation = ProcessCancellation()
        return try await withTaskCancellationHandler(operation: {
            try await withCheckedThrowingContinuation { continuation in
                DispatchQueue.global(qos: .userInitiated).async {
                    do {
                        let scratch = FileManager.default.homeDirectoryForCurrentUser
                            .appendingPathComponent(".hermes/cache/scratch/subler-automation-processes", isDirectory: true)
                        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
                        let directory = scratch.appendingPathComponent(UUID().uuidString, isDirectory: true)
                        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                        defer { try? FileManager.default.removeItem(at: directory) }
                        let outURL = directory.appendingPathComponent("stdout")
                        let errURL = directory.appendingPathComponent("stderr")
                        FileManager.default.createFile(atPath: outURL.path, contents: nil)
                        FileManager.default.createFile(atPath: errURL.path, contents: nil)
                        let out = try FileHandle(forWritingTo: outURL)
                        let err = try FileHandle(forWritingTo: errURL)
                        defer { try? out.close(); try? err.close() }
                        let process = Process()
                        process.executableURL = executable
                        process.arguments = arguments
                        process.standardOutput = out
                        process.standardError = err
                        if cancellation.isCancelled { throw CancellationError() }
                        try process.run()
                        let deadline = Date().addingTimeInterval(timeout)
                        while process.isRunning {
                            if cancellation.isCancelled || Date() >= deadline {
                                process.terminate()
                                // Only terminate our osascript worker, never Subler or its global queue.
                                let grace = Date().addingTimeInterval(2)
                                while process.isRunning && Date() < grace { Thread.sleep(forTimeInterval: 0.02) }
                                if process.isRunning { kill(process.processIdentifier, SIGKILL) }
                                process.waitUntilExit()
                                if cancellation.isCancelled { throw CancellationError() }
                                throw AutomationServiceError.message("\(executable.lastPathComponent) timed out after \(timeout) seconds. Subler may still be working; inspect this job's queue item before retrying.")
                            }
                            Thread.sleep(forTimeInterval: 0.02)
                        }
                        process.waitUntilExit()
                        let errors = String(decoding: try Data(contentsOf: errURL), as: UTF8.self)
                        guard process.terminationStatus == 0 else {
                            throw AutomationServiceError.message("\(executable.lastPathComponent) failed (\(process.terminationStatus)): \(errors.trimmingCharacters(in: .whitespacesAndNewlines))")
                        }
                        continuation.resume(returning: String(decoding: try Data(contentsOf: outURL), as: UTF8.self).trimmingCharacters(in: .newlines))
                    } catch { continuation.resume(throwing: error) }
                }
            }
        }, onCancel: { cancellation.cancel() })
    }
}
