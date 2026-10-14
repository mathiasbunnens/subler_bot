import Foundation

/// Counts films since the last manual reset, independently of batch boundaries.
/// The initial count comes only from the persistent counter, never job history.
public struct BatchCounter: Equatable, Sendable {
    public private(set) var completed = 0
    public private(set) var isOpen = false

    public init(completed: Int = 0) { self.completed = completed }

    public static func holdsBatch(_ job: MovieJob) -> Bool {
        switch job.status {
        case .pending: return !job.needsSelection
        case .importing, .prettifying, .fetchingMetadata, .converting, .validating, .waitingForServer, .transferring: return true
        case .completed, .failed, .paused: return false
        }
    }

    public mutating func jobStarted() {
        guard !isOpen else { return }
        isOpen = true
    }

    /// Called only after the completion was durably persisted.
    public mutating func recordCompletion() { completed += 1 }

    /// Called when the worker finishes; closes the batch once no job holds it.
    public mutating func workerFinished(remaining jobs: [MovieJob]) {
        if !jobs.contains(where: Self.holdsBatch) { isOpen = false }
    }

    /// Manual reset: history is untouched and an open batch stays open.
    public mutating func reset() { completed = 0 }
}
