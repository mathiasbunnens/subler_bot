import Foundation

public enum InterventionRemovalError: LocalizedError {
    case missingJob, activeJob, ineligibleStatus, unsupportedStore, failedReadback
    public var errorDescription: String? {
        switch self {
        case .missingJob: return "Tâche absente."
        case .activeJob: return "Cette tâche est en cours de traitement. Attendez sa fin avant de la supprimer de la liste."
        case .ineligibleStatus: return "Seules les tâches suspendues, en échec ou en attente du serveur peuvent être supprimées de la liste."
        case .unsupportedStore: return "Version de la file non prise en charge. Aucun état ne sera écrasé."
        case .failedReadback: return "La sauvegarde de la file n’a pas pu être vérifiée."
        }
    }
}

/// Removal is only queue bookkeeping; it never operates on Subler or media files.
public enum InterventionRemovalPolicy {
    public static func validate(_ id: UUID, jobs: [MovieJob], activeID: UUID?) throws -> MovieJob {
        guard let job = jobs.first(where: { $0.id == id }) else { throw InterventionRemovalError.missingJob }
        guard activeID != id else { throw InterventionRemovalError.activeJob }
        guard [.paused, .failed, .waitingForServer].contains(job.status) || (job.status == .pending && job.needsSelection) else {
            throw InterventionRemovalError.ineligibleStatus
        }
        return job
    }
}
