import SwiftUI
import AutomationCore

struct PermissionSettingsView: View {
    @ObservedObject var permissions: PermissionPreparationService
    var retry: () -> Void
    var body: some View {
        Form {
            Section {
                HStack(alignment: .top) {
                    Image(systemName: symbol).foregroundStyle(permissions.state.isReady ? Color.green : Color.orange)
                    VStack(alignment: .leading, spacing: 8) {
                        Text(title).font(.headline)
                        Text(detail).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                    }
                    Spacer()
                }
                Button(permissions.state == .requesting ? "Vérification…" : "Préparer / Réessayer les autorisations", action: retry)
                    .disabled(permissions.state == .requesting)
                    .buttonStyle(.borderless).foregroundStyle(Color.accentColor)
            } header: { Label("Avant la conversion", systemImage: "checkmark.shield") }
            Section {
                Text("Subler : contrôle de l’application uniquement, sans importer de film ni modifier sa file.")
                Text("Source : lecture du dossier. Dossier temporaire : écriture d’un petit fichier unique, immédiatement supprimé.")
                Text(permissions.networkMessage)
                Text("Un partage absent n’est jamais monté par cette vérification. Une fois monté, un nouvel accès nécessite une préparation explicite avant le travail.")
            } header: { Label("Accès nécessaires", systemImage: "folder.badge.gearshape") }
            Section {
                Text(notificationDetail)
                Text("Les notifications sont facultatives : un refus ne bloque pas la conversion.")
            } header: { Label("Notifications", systemImage: "bell") }
            Section {
                Text("La configuration autorisée est enregistrée puis revérifiée sans nouvelle demande. macOS peut révoquer un accès à tout moment ; aucune autorisation n’est garantie définitivement.")
                Text("Aucun mot de passe, aucune permission Accessibilité ni Accès complet au disque ne sont nécessaires.")
                Text("Enregistrez d’abord les nouveaux chemins. Le bouton prépare la configuration enregistrée et les dossiers des films en attente.")
            } header: { Label("Confidentialité", systemImage: "lock.shield") }
        }
        .font(.callout).formStyle(.grouped)
    }
    private var title: String {
        switch permissions.state {
        case .unprepared: return "Autorisations à préparer"
        case .requesting: return "Préparation en cours"
        case .ready: return "Accès vérifiés pour cette configuration"
        case .blocked: return "Traitement bloqué : autorisation requise"
        }
    }
    private var detail: String {
        switch permissions.state {
        case .unprepared: return "Préparez les accès avant le premier film."
        case .requesting: return "Répondez aux demandes natives de macOS. Aucun film n’est importé."
        case .ready: return "Les accès disponibles ont été vérifiés. Un partage absent reste à vérifier après montage."
        case .blocked(let message): return message
        }
    }
    private var symbol: String {
        switch permissions.state {
        case .ready: return "checkmark.circle.fill"
        case .requesting: return "hourglass"
        default: return "exclamationmark.shield"
        }
    }
    private var notificationDetail: String {
        switch permissions.notificationStatus {
        case .granted: return "Notifications autorisées."
        case .denied: return "Notifications refusées. Vous pouvez les activer dans Réglages Système → Notifications."
        case .undetermined: return "Notifications désactivées dans l’application ou autorisation non demandée."
        }
    }
}
