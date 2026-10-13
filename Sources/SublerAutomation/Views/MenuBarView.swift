import SwiftUI
import AutomationCore

struct TransferProgressView: View {
    let sample: TransferProgress
    var body: some View {
        let done = sample.verificationBytes ?? sample.bytesCopied
        let fraction = sample.totalBytes > 0 ? Double(done) / Double(sample.totalBytes) : 0
        VStack(alignment: .leading, spacing: 6) {
            Text(sample.verificationBytes == nil ? "Copie SMB" : "Vérification SHA-256").bold()
            SwiftUI.ProgressView(value: fraction)
            Text("\(Int(fraction * 100)) % — \(ByteCountFormatter.string(fromByteCount: done, countStyle: .file)) / \(ByteCountFormatter.string(fromByteCount: sample.totalBytes, countStyle: .file))")
            Text(String(format: "%.1f Mo/s", sample.bytesPerSecond / 1_000_000))
            if let remaining = sample.secondsRemaining, remaining.isFinite {
                Text("Temps restant estimé : \(Int(remaining)) s")
            }
            if sample.verificationBytes == sample.totalBytes { Text("Lecture terminée — contrôle et publication…") }
            else if sample.verificationBytes == nil && sample.bytesCopied == sample.totalBytes { Text("Synchronisation du fichier serveur…") }
        }.font(.caption).foregroundStyle(.secondary)
    }
}

struct MenuBarView: View {
    @ObservedObject var queue: JobQueueService
    private let stages: [(String, [JobStatus])] = [
        ("Importation MKV", [.importing]), ("Noms des pistes audio", [.prettifying]),
        ("Métadonnées", [.fetchingMetadata]), ("Conversion MP4", [.converting]),
        ("Validation", [.validating]), ("Transfert SMB", [.waitingForServer, .transferring])
    ]
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Subler Automation", systemImage: "film").font(.headline)
            Divider()
            if let job = queue.currentJob {
                Text(job.displayName).font(.headline).lineLimit(2)
                Text(label(job.status)).foregroundStyle(.secondary)
                let current = stages.firstIndex { $0.1.contains(job.status) } ?? -1
                ForEach(Array(stages.enumerated()), id: \.offset) { index, stage in
                    Label(stage.0, systemImage: index < current ? "checkmark.circle.fill" : index == current ? "circle.inset.filled" : "circle")
                        .foregroundStyle(index == current ? Color.accentColor : Color.secondary)
                }
                if let progress = queue.progress { TransferProgressView(sample: progress) }
                else if [.importing, .fetchingMetadata, .converting, .validating].contains(job.status) {
                    HStack { SwiftUI.ProgressView().controlSize(.small); Text(label(job.status)).font(.caption) }
                }
                if job.status == .transferring { Button("Suspendre le transfert") { queue.cancelTransfer() } }
            } else {
                Text(queue.settings.paused ? "File en pause" : "Inactif — attente de MKV stables (60 s)").foregroundStyle(.secondary)
            }
            if let message = queue.message { Text(message).font(.caption).foregroundStyle(.red).textSelection(.enabled) }
            Text("En attente : \(queue.jobs.filter { ![.completed, .failed, .paused].contains($0.status) }.count)   Terminés : \(queue.jobs.filter { $0.status == .completed }.count)").font(.caption)
            let interventions = queue.jobs.filter { [.failed, .paused, .waitingForServer].contains($0.status) }
            if !interventions.isEmpty {
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(interventions) { job in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(job.displayName).font(.subheadline).bold()
                                if let error = job.error { Text(error).font(.caption).foregroundStyle(.secondary).textSelection(.enabled) }
                                if job.needsSelection, let choices = queue.candidates[job.id], !choices.isEmpty {
                                    Menu("Choisir les métadonnées…") {
                                        ForEach(choices) { choice in Button("\(choice.title) (\(choice.year))") { queue.select(choice, for: job.id) } }
                                    }
                                }
                                HStack {
                                    Button("Réessayer") { queue.retry(job.id) }
                                    if job.conflict {
                                        Button("Ignorer") { queue.ignore(job.id) }
                                        Button("Remplacer…") { queue.confirmReplacement(job.id) }
                                    }
                                }.controlSize(.small)
                            }
                        }
                    }
                }.frame(maxHeight: 180)
            }
            Divider()
            Button("Ajouter des films…", systemImage: "plus") { queue.addMovies() }
            Button(queue.settings.paused ? "Démarrer" : "Pause après le film en cours", systemImage: queue.settings.paused ? "play" : "pause") { queue.togglePause() }
            Button("Ouvrir le dossier source", systemImage: "folder") { queue.openSource() }
            SettingsLink { Label("Réglages…", systemImage: "gearshape") }
                .simultaneousGesture(TapGesture().onEnded { NSApplication.shared.activate(ignoringOtherApps: true) })
            Button("Voir les journaux", systemImage: "doc.text") { queue.openLogs() }
            Divider()
            Button("Quitter") { queue.quit() }.keyboardShortcut("q")
        }.padding(16).frame(width: 360)
        .task { if queue.settings.notifications { queue.requestNotifications() } }
    }
    private func label(_ status: JobStatus) -> String {
        switch status {
        case .pending: return "En attente"
        case .importing: return "Importation MKV"
        case .prettifying: return "Embellissement audio"
        case .fetchingMetadata: return "Recherche des métadonnées"
        case .converting: return "Conversion en cours"
        case .validating: return "Validation du MP4"
        case .waitingForServer: return "Attente du serveur SMB"
        case .transferring: return "Transfert SMB"
        case .completed: return "Terminé"
        case .failed: return "Erreur"
        case .paused: return "Intervention nécessaire"
        }
    }
}
