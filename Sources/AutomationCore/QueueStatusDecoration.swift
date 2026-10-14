import Foundation

/// Metadata confirmation takes priority over session completion, even during other work.
public enum QueueStatusDecoration: Equatable, Sendable {
    case none, metadataConfirmation, finished

    public static func resolve(jobs: [MovieJob], currentJob: MovieJob?, message: String?, hasCompletedThisSession: Bool) -> Self {
        if jobs.contains(where: { $0.needsSelection }) { return .metadataConfirmation }
        if hasCompletedThisSession && currentJob == nil && message == nil && !jobs.isEmpty && jobs.allSatisfy({
            $0.status == .completed && $0.error == nil && !$0.needsSelection
        }) { return .finished }
        return .none
    }

    public var accessibilityDescription: String {
        switch self {
        case .none: return "Subler Automation"
        case .metadataConfirmation: return "Métadonnées à confirmer"
        case .finished: return "Tous les films sont terminés"
        }
    }

    public var dockBadgeLabel: String? { self == .metadataConfirmation ? "!" : nil }
}
