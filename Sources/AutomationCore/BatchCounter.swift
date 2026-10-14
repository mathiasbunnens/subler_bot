import Foundation

/// Counts films completed in the current batch, never the whole history.
///
/// Batch boundary: a batch opens at the first effective job start while no batch
/// is open, which resets the count. It stays open while any job still holds it
/// (runnable pending work or a validated film waiting for the server). Pausing,
/// resuming or adding films during an open batch never resets the count.
/// Interventions (failed, paused, metadata selection) do not hold a batch: an old
/// unresolved film must not prevent the next batch from starting at zero.
public struct BatchCounter: Equatable, Sendable {
    public private(set) var completed = 0
    public private(set) var isOpen = false

    public init() {}

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
        completed = 0
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
