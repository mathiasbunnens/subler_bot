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
    public var manualMetadata: ManualMovieMetadata?
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
    public var canEditMetadata: Bool {
        !validated && localPath == nil && (needsSelection || [.failed, .paused].contains(status))
    }
    public mutating func applyManualMetadata(_ metadata: ManualMovieMetadata, isActive: Bool) throws {
        guard !isActive, canEditMetadata else {
            throw AutomationServiceError.message("La saisie est réservée aux tâches en intervention avant conversion. Une sortie existante doit être examinée avant de modifier son identité.")
        }
        manualMetadata = metadata; title = metadata.title; year = metadata.year
        candidateIndex = nil; candidateRaw = nil; needsSelection = false
        status = .pending; error = nil; validated = false; validatedDigest = nil
    }
    public var metadataWarning: String? {
        if manualMetadata != nil { return "Métadonnées saisies manuellement — titre et année uniquement ; affiche et détails fournisseur non garantis." }
        if needsSelection { return "Métadonnées manquantes ou non confirmées : titre et année requis avant conversion et envoi." }
        return nil
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
