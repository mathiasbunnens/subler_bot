import SwiftUI
import AppKit
import ServiceManagement

struct SettingsView: View {
    @ObservedObject var queue: JobQueueService
    @State private var draft = AppSettings()
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var serviceError: String?
    var body: some View {
        Form {
            Section("Dossiers locaux") {
                folder("MKV surveillés", path: $draft.sourcePath)
                folder("MP4 temporaires", path: $draft.temporaryPath)
                Toggle("Surveiller automatiquement le dossier", isOn: $draft.watchFolder)
                Text("Attente de 60 secondes sans modification et absence de fichier ouvert en écriture. Pour une copie susceptible de longues pauses, copiez sous .part puis renommez en .mkv à la fin.").font(.caption).foregroundStyle(.secondary)
            }
            Section("Serveur SMB") {
                TextField("Adresse SMB", text: $draft.smb.serverURL)
                TextField("Utilisateur", text: $draft.smb.username)
                TextField("Montage attendu", text: $draft.smb.expectedMountPath)
                Text("Le montage SMB et son origine sont vérifiés. Aucun mot de passe enregistré par cette application ; utilisation du Trousseau existant.").font(.caption).foregroundStyle(.secondary)
            }
            Section("Application") {
                Toggle("Notifications", isOn: $draft.notifications)
                Button("Autoriser les notifications…") { queue.requestNotifications() }
                Toggle("Lancer à l’ouverture de session", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in
                        do {
                            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                        } catch { serviceError = error.localizedDescription; launchAtLogin = SMAppService.mainApp.status == .enabled }
                    }
                Toggle("Nettoyer les MP4 locaux après transfert vérifié", isOn: $draft.cleanupTemporary)
                Text("Les MKV originaux ne sont jamais supprimés. La pause prend effet à la fin du film en cours. Subler conserve tous ses réglages.").font(.caption).foregroundStyle(.secondary)
            }
            if let serviceError { Text(serviceError).foregroundStyle(.red) }
            if let message = queue.message { Text(message).foregroundStyle(.red) }
            Text("Les réglages de destination et de nettoyage sont figés par film au début de sa conversion. Les modifications s’appliquent aux films suivants.").font(.caption).foregroundStyle(.secondary)
            Button("Enregistrer") {
                draft.paused = queue.settings.paused
                queue.applySettings(draft)
                if queue.settings.notifications { queue.requestNotifications() }
            }
        }.formStyle(.grouped).frame(width: 610, height: 620)
        .onAppear { draft = queue.settings }
    }
    private func folder(_ title: String, path: Binding<String>) -> some View {
        HStack {
            TextField(title, text: path)
            Button("Choisir…") {
                let panel = NSOpenPanel(); panel.canChooseFiles = false; panel.canChooseDirectories = true; panel.canCreateDirectories = true
                if panel.runModal() == .OK, let url = panel.url { path.wrappedValue = url.path }
            }
        }
    }
}
