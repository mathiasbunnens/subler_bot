import Foundation

/// Interactive authentication is demand-driven, never part of idle polling.
public struct SMBAuthenticationGate {
    private struct ShareKey: Hashable {
        let serverURL: String
        let username: String
        init(_ configuration: SMBConfiguration) {
            serverURL = configuration.serverURL; username = configuration.username
        }
    }
    private var attempted = Set<ShareKey>()
    public init() {}
    public mutating func allowRetry(configuration: SMBConfiguration) {
        attempted.remove(ShareKey(configuration))
    }
    public mutating func begin(job: MovieJob, configuration: SMBConfiguration, shareIsMounted: Bool) -> Bool {
        guard job.validated, job.status == .waitingForServer, !shareIsMounted else { return false }
        return attempted.insert(ShareKey(configuration)).inserted
    }
}
