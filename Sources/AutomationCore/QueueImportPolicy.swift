import Foundation

public enum QueueImportPolicy {
    public static func shouldAdd(path: String, fingerprint: String, jobs: [MovieJob], explicit: Bool) -> Bool {
        blockingJob(path: path, fingerprint: fingerprint, jobs: jobs, explicit: explicit) == nil
    }
    public static func blockingJob(path: String, fingerprint: String, jobs: [MovieJob], explicit: Bool) -> MovieJob? {
        jobs.first {
            if explicit && $0.status == .completed { return false }
            return $0.fingerprint == fingerprint || ($0.sourcePath == path && $0.status != .completed)
        }
    }
}
