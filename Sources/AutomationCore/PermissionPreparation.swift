import Foundation

public struct PermissionScope: Codable, Equatable, Sendable {
    public let sourcePath: String
    public let temporaryPath: String
    public let serverURL: String
    public let expectedMountPath: String
    public let notifications: Bool
    public init(sourcePath: String, temporaryPath: String, serverURL: String, expectedMountPath: String, notifications: Bool) {
        self.sourcePath = sourcePath; self.temporaryPath = temporaryPath
        self.serverURL = serverURL; self.expectedMountPath = expectedMountPath; self.notifications = notifications
    }
}
public struct PermissionGrant: Codable, Equatable, Sendable {
    public let scope: PermissionScope
    public let networkPath: String?
    public init(scope: PermissionScope, networkPath: String?) { self.scope = scope; self.networkPath = networkPath }
}
public enum PermissionDecision: Equatable, Sendable { case granted, denied, undetermined }
public enum PermissionPreparationState: Equatable, Sendable {
    case unprepared, requesting, ready, blocked(String)
    public var isReady: Bool { self == .ready }
}

/// No native dependencies: all permission requests and persistence are explicitly injected.
@MainActor public struct PermissionOperations {
    public var automation: (Bool) async -> PermissionDecision
    public var sourceRead: (String, Bool) async -> String?
    public var temporaryWrite: (String, Bool) async -> String?
    public var mountedShare: (PermissionScope) async -> String?
    public var networkRead: (String, Bool) async -> String?
    public var notifications: (Bool) async -> PermissionDecision
    public var load: () throws -> PermissionGrant?
    public var save: (PermissionGrant) throws -> Void
    public init(automation: @escaping (Bool) async -> PermissionDecision, sourceRead: @escaping (String, Bool) async -> String?, temporaryWrite: @escaping (String, Bool) async -> String?, mountedShare: @escaping (PermissionScope) async -> String?, networkRead: @escaping (String, Bool) async -> String?, notifications: @escaping (Bool) async -> PermissionDecision, load: @escaping () throws -> PermissionGrant?, save: @escaping (PermissionGrant) throws -> Void) {
        self.automation = automation; self.sourceRead = sourceRead; self.temporaryWrite = temporaryWrite
        self.mountedShare = mountedShare; self.networkRead = networkRead; self.notifications = notifications
        self.load = load; self.save = save
    }
}

@MainActor public final class PermissionPreparation {
    public private(set) var state: PermissionPreparationState = .unprepared
    public private(set) var networkMessage = "Partage non monté : vérification différée, sans connexion automatique."
    public private(set) var notificationStatus: PermissionDecision = .undetermined
    public private(set) var checkedScope: PermissionScope?
    public private(set) var hasRecordedScope = false
    private let operations: PermissionOperations
    public init(operations: PermissionOperations) { self.operations = operations }
    public func prepare(_ scope: PermissionScope) async { await check(scope, request: true) }
    public func recheck(_ scope: PermissionScope) async { await check(scope, request: false) }
    private func check(_ scope: PermissionScope, request: Bool) async {
        guard state != .requesting else { return }
        state = .requesting
        checkedScope = nil
        hasRecordedScope = false
        guard [scope.sourcePath, scope.temporaryPath].allSatisfy(LocalPathPolicy.isValidAbsolutePath) else {
            state = .blocked("Choisissez des dossiers avec des chemins absolus, sans traversée de répertoire."); return
        }
        // An empty server means "not configured yet" (first installation): conversion
        // may proceed and validated films wait locally until a share is configured.
        if !scope.serverURL.isEmpty {
            guard let server = URLComponents(string: scope.serverURL), server.scheme?.lowercased() == "smb", server.host != nil,
                  server.user == nil, server.password == nil, server.query == nil, server.fragment == nil,
                  server.path.split(separator: "/").count == 1 else {
                state = .blocked("Adresse SMB attendue sans identifiants intégrés : smb://serveur/partage."); return
            }
        }
        do {
            let previous = try operations.load()
            hasRecordedScope = previous?.scope == scope
            guard request || previous?.scope == scope else {
                state = .blocked("Configuration nouvelle : préparez les autorisations dans les réglages."); return
            }
            guard await operations.automation(request) == .granted else {
                state = .blocked("Autorisez le contrôle de Subler dans Réglages Système → Confidentialité et sécurité → Automatisation."); return
            }
            if let error = await operations.sourceRead(scope.sourcePath, request) { state = .blocked("Dossier source : " + error); return }
            if let error = await operations.temporaryWrite(scope.temporaryPath, request) { state = .blocked("Dossier temporaire : " + error); return }
            var networkPath: String?
            if let mounted = await operations.mountedShare(scope) {
                guard request || previous?.networkPath == mounted else {
                    state = .blocked("Partage monté non préparé : réessayez les autorisations dans les réglages."); return
                }
                if let error = await operations.networkRead(mounted, request) { state = .blocked("Volume réseau : " + error); return }
                networkPath = mounted; networkMessage = "Lecture du partage monté vérifiée."
            } else {
                networkMessage = "Partage non monté : vérification différée, sans connexion automatique."
            }
            notificationStatus = scope.notifications ? await operations.notifications(request) : .undetermined
            // Notifications are optional: refusal never blocks conversion.
            if request { try operations.save(.init(scope: scope, networkPath: networkPath)) }
            checkedScope = scope
            state = .ready
        } catch { state = .blocked("Sauvegarde des autorisations impossible : \(error.localizedDescription)") }
    }
}
