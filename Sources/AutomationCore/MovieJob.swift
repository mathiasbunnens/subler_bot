import Foundation

public enum JobStatus: String, Codable, CaseIterable, Sendable {
    case pending, importing, prettifying, fetchingMetadata, converting, validating
    case waitingForServer, transferring, completed, failed, paused
}

public struct MovieJob: Codable, Identifiable, Sendable {
    public let id: UUID
    public let sourcePath: String
    public var fingerprint: String
    public var status: JobStatus = .pending
    public var createdAt = Date()
    public var updatedAt = Date()
    public var title: String?
    public var year: Int?
    public var candidateIndex: Int?
    public var candidateRaw: String?
    public var documentID: Int?
    public var localPath: String?
    public var destinationPath: String?
    public var validated = false
    public var validatedDigest: String?
    public var workRoot: String?
    public var smbConfiguration: SMBConfiguration?
    public var cleanupAfterTransfer: Bool?
    public var backupPath: String?
    public var error: String?
    public var needsSelection = false
    public var conflict = false
    public init(sourcePath: String, fingerprint: String, id: UUID = UUID()) {
        self.id = id; self.sourcePath = sourcePath; self.fingerprint = fingerprint
    }
    public var displayName: String {
        if let title, let year { return MovieNaming.name(title: title, year: year) }
        return URL(fileURLWithPath: sourcePath).deletingPathExtension().lastPathComponent
    }
    public mutating func recover() {
        // Never infer conversion success from file existence after a crash.
        if status == .pending && needsSelection { status = .paused }
        switch status {
        case .completed, .failed, .paused, .pending: break
        case .waitingForServer, .transferring: status = validated ? .waitingForServer : .pending
        default: status = .pending; validated = false
        }
    }
}
