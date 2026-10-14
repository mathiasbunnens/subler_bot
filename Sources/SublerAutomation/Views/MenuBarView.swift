import SwiftUI
import AppKit
import AutomationCore

private struct MenuContentHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct MenuRootHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

/// The MenuBarExtra popup window grows with its content but does not always
/// shrink back (e.g. after an intervention or error card disappears), leaving
/// an empty translucent band under the footer. Fit the popup window to the
/// measured content height every time it changes, keeping its top edge under
/// the menu bar. Other windows (normal-app main window) are left untouched.
struct MenuWindowAutoSizer: NSViewRepresentable {
    let height: CGFloat

    func makeNSView(context: Context) -> NSView { NSView() }
    func updateNSView(_ view: NSView, context: Context) {
        let target = height
        DispatchQueue.main.async { Self.fit(view.window, contentHeight: target) }
    }

    static func isMenuBarPopup(_ window: NSWindow) -> Bool {
        String(describing: type(of: window)).contains("MenuBarExtra")
    }

    static func fit(_ window: NSWindow?, contentHeight: CGFloat) {
        guard let window, contentHeight > 0, isMenuBarPopup(window) else { return }
        var frame = window.frame
        let wanted = window.frameRect(forContentRect: NSRect(x: 0, y: 0, width: frame.width, height: contentHeight)).height
        guard abs(frame.height - wanted) > 0.5 else { return }
        frame.origin.y += frame.height - wanted
        frame.size.height = wanted
        window.setFrame(frame, display: true)
    }
}

struct TransferProgressView: View {
    let sample: TransferProgress
    var body: some View {
        let done = sample.verificationBytes ?? sample.bytesCopied
        let fraction = sample.totalBytes > 0 ? Double(done) / Double(sample.totalBytes) : 0
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(sample.verificationBytes == nil ? "Copie SMB" : "Vérification SHA-256")
                    .fontWeight(.semibold).foregroundStyle(.primary)
                Spacer()
                Text("\(Int(fraction * 100)) %").monospacedDigit().foregroundStyle(Color.accentColor)
            }
            SwiftUI.ProgressView(value: fraction)
            Text("\(ByteCountFormatter.string(fromByteCount: done, countStyle: .file)) / \(ByteCountFormatter.string(fromByteCount: sample.totalBytes, countStyle: .file))")
                .monospacedDigit()
            HStack {
                Text(String(format: "%.1f Mo/s", sample.bytesPerSecond / 1_000_000))
                Spacer()
                if let remaining = sample.secondsRemaining, let formatted = RemainingTimeFormatter.string(seconds: remaining) {
                    Text("Reste ≈ \(formatted)")
                }
            }.font(.caption2).monospacedDigit()
            if sample.verificationBytes == sample.totalBytes { Text("Lecture terminée — contrôle et publication…") }
            else if sample.verificationBytes == nil && sample.bytesCopied == sample.totalBytes { Text("Synchronisation du fichier serveur…") }
        }.font(.caption).foregroundStyle(.secondary)
    }
}

struct MenuBarView: View {
    @ObservedObject var queue: JobQueueService
    @Environment(\.openSettings) private var openSettings
    @State private var contentHeight: CGFloat = 0
    @State private var rootHeight: CGFloat = 0
    // Keep drafts above the short/scroll container switch, keyed by job identity.
    @State private var manualDrafts: [UUID: ManualMetadataDraft] = [:]
    // Reserve space for the header, summary, footer, padding and menu-bar clearance.
    private var contentHeightLimit: CGFloat {
        max(80, min(460, (NSScreen.main?.visibleFrame.height ?? 800) - 260))
    }
    private let stages: [(String, [JobStatus])] = [
        ("Importation MKV", [.importing]), ("Noms des pistes audio", [.prettifying]),
        ("Métadonnées", [.fetchingMetadata]), ("Conversion MP4", [.converting]),
        ("Validation", [.validating]), ("Transfert SMB", [.waitingForServer, .transferring])
    ]
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            summary
            Group {
                if contentHeight > contentHeightLimit {
                    ScrollView { menuContent }
                        .frame(height: contentHeightLimit)
                } else {
                    menuContent
                }
            }
            .onPreferenceChange(MenuContentHeightKey.self) { height in
                if height > 0 { contentHeight = height }
            }
            Divider()
            footer
        }
        .padding(14).frame(width: 380)
        .fixedSize(horizontal: false, vertical: true)
        .background(.regularMaterial)
        .background {
            GeometryReader { geometry in
                Color.clear.preference(key: MenuRootHeightKey.self, value: geometry.size.height)
            }
        }
        .onPreferenceChange(MenuRootHeightKey.self) { height in
            if height > 0 { rootHeight = height }
        }
        .background(MenuWindowAutoSizer(height: rootHeight))
        .controlSize(.small)
    }

    // Short panels keep their intrinsic height. Scrolling exists only when the
    // complete content exceeds the available screen space, not as an empty slot.
    private var menuContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let job = queue.currentJob { activeCard(job) }
            else { idleCard }
            ForEach(queue.jobs.filter { value in value.manualMetadata != nil && value.id != queue.activeID && !interventions.contains(where: { $0.id == value.id }) }.suffix(3)) { job in
                card {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(job.displayName).font(.caption).bold()
                        metadataWarning(job)
                    }
                }
            }
            if !queue.permissions.state.isReady {
                card {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Autorisations avant traitement", systemImage: "hand.raised")
                            .font(.subheadline).bold()
                        if case .blocked(let reason) = queue.permissions.state {
                            Text(reason).font(.caption).fixedSize(horizontal: false, vertical: true)
                        } else {
                            Text("Préparation des accès macOS. Aucun film ne sera lancé avant validation.")
                                .font(.caption).fixedSize(horizontal: false, vertical: true)
                        }
                        Button("Préparer les autorisations…") { queue.preparePermissions() }
                            .buttonStyle(.borderless).foregroundStyle(Color.accentColor)
                            .disabled(queue.permissions.state == .requesting || queue.activeID != nil)
                    }
                }
            }
            if let message = queue.message {
                card {
                    Label {
                        Text(message).textSelection(.enabled)
                    } icon: { Image(systemName: "exclamationmark.triangle.fill") }
                        .font(.caption).foregroundStyle(Color.red)
                }
            }
            if !interventions.isEmpty {
                Text("À VÉRIFIER").font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
                ForEach(interventions) { job in interventionCard(job) }
            }
        }
        .padding(.vertical, 1)
        .frame(maxWidth: .infinity, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
        .background {
            GeometryReader { geometry in
                Color.clear.preference(key: MenuContentHeightKey.self, value: geometry.size.height)
            }
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "film.stack").font(.title3).foregroundStyle(Color.accentColor)
            VStack(alignment: .leading, spacing: 2) {
                Text("Subler Automation").font(.system(size: 14, weight: .semibold))
                Text("MKV → MP4 → SMB").font(.caption2).foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            Label(statusTitle, systemImage: statusSymbol)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(statusColor)
                .padding(.horizontal, 8).padding(.vertical, 5)
                .background(statusColor.opacity(0.12), in: Capsule())
        }
    }

    private var summary: some View {
        card {
            HStack(spacing: 0) {
                metric(queue.jobs.filter { $0.status == .pending }.count, title: "En attente", color: .primary)
                Divider().frame(height: 28)
                metric(queue.batch.completed, title: "Terminés", color: .primary)
                    .overlay(alignment: .topTrailing) {
                        Button { queue.resetBatchCounter() } label: {
                            Image(systemName: "arrow.counterclockwise").font(.system(size: 9, weight: .semibold))
                                .frame(width: 16, height: 16).contentShape(Rectangle())
                        }
                        .buttonStyle(.borderless).foregroundStyle(.secondary)
                        .disabled(queue.batch.completed == 0)
                        .help("Remettre le compteur à zéro (l’historique est conservé). Il repart aussi à zéro au lancement d’un nouveau lot.")
                        .accessibilityLabel("Remettre à zéro le compteur des films terminés")
                        .offset(x: -4, y: -4)
                    }
                Divider().frame(height: 28)
                metric(interventions.count, title: "À vérifier", color: interventions.isEmpty ? .secondary : .orange)
            }
        }
    }

    private func metric(_ value: Int, title: String, color: Color) -> some View {
        VStack(spacing: 3) {
            Text(String(value)).font(.system(size: 20, weight: .semibold)).monospacedDigit().foregroundStyle(color)
            Text(title).font(.caption2).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title) : \(value)")
    }

    private func activeCard(_ job: MovieJob) -> some View {
        card {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("FILM EN COURS").font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
                    Spacer()
                    if queue.settings.paused {
                        Text("Pause ensuite").font(.caption2).foregroundStyle(Color.orange)
                    }
                }
                if [.waitingForServer, .transferring].contains(job.status) {
                    // Poster of the film being sent; keyed by job so a previous cover never lingers.
                    HStack(alignment: .top, spacing: 10) {
                        PosterView(path: job.posterPath.flatMap {
                            PosterExtractor.isOwned($0, workRoot: job.workRoot, jobID: job.id) ? $0 : nil
                        }).id(job.id)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(job.displayName).font(.system(size: 14, weight: .semibold)).lineLimit(3).textSelection(.enabled)
                            metadataWarning(job)
                        }
                    }
                } else {
                    Text(job.displayName).font(.system(size: 14, weight: .semibold)).lineLimit(2).textSelection(.enabled)
                    metadataWarning(job)
                }
                if let progress = queue.progress { TransferProgressView(sample: progress) }
                else {
                    HStack(spacing: 6) {
                        if [.importing, .prettifying, .fetchingMetadata, .converting, .validating].contains(job.status) {
                            SwiftUI.ProgressView().controlSize(.mini)
                        }
                        Text(label(job.status)).font(.caption).foregroundStyle(.secondary)
                    }
                }
                Divider()
                stageGrid(job.status)
                if job.status == .transferring {
                    Button("Suspendre le transfert", systemImage: "pause.circle") { queue.cancelTransfer() }
                        .buttonStyle(.borderless)
                }
            }
        }
    }

    private func stageGrid(_ status: JobStatus) -> some View {
        let current = stages.firstIndex { $0.1.contains(status) } ?? -1
        return LazyVGrid(columns: [GridItem(.flexible(), alignment: .leading), GridItem(.flexible(), alignment: .leading)], alignment: .leading, spacing: 7) {
            ForEach(Array(stages.enumerated()), id: \.offset) { index, stage in
                Label(stage.0, systemImage: index < current ? "checkmark.circle.fill" : index == current ? "circle.inset.filled" : "circle")
                    .font(.system(size: 11, weight: index == current ? .semibold : .regular))
                    .foregroundStyle(index == current ? Color.accentColor : Color.secondary)
                    .accessibilityLabel("\(stage.0) : \(index < current ? "effectué" : index == current ? "en cours" : "à venir")")
            }
        }
    }

    private var idleCard: some View {
        card {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: queue.settings.paused ? "pause.circle" : "tray")
                    .font(.title2).foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 4) {
                    Text(queue.settings.paused ? "File en pause" : "Prêt pour le prochain film").font(.subheadline).bold()
                    Text(queue.settings.paused ? "Démarrez pour reprendre les films en attente." : queue.settings.watchFolder ? "Le dossier source est surveillé. Les MKV doivent être stables pendant 10 s." : "Ajoutez des films ou activez la surveillance dans les réglages.")
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func interventionCard(_ job: MovieJob) -> some View {
        card {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: job.needsSelection ? "text.magnifyingglass" : "exclamationmark.circle")
                        .foregroundStyle(Color.orange)
                    Text(job.displayName).font(.subheadline).bold().lineLimit(2)
                }
                Text(label(job.status)).font(.caption2).foregroundStyle(.secondary)
                metadataWarning(job)
                if let error = job.error {
                    Text(error).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if job.needsSelection, let choices = queue.candidates[job.id], !choices.isEmpty {
                    candidateRows(choices, for: job)
                }
                if job.canEditMetadata {
                    ManualMetadataForm(queue: queue, job: job, draft: manualDraft(job)).id(job.id)
                }
                HStack(spacing: 6) {
                    if job.status == .waitingForServer, job.validated {
                        Button("Connecter…", systemImage: "externaldrive.badge.wifi") { queue.connectServer(for: job.id) }
                            .disabled(queue.activeID != nil)
                            .help("Connexion native macOS avec votre utilisateur et mot de passe ; reprenez la file si elle est en pause")
                    }
                    Button("Réessayer", systemImage: "arrow.clockwise") { queue.retry(job.id) }
                    if job.conflict {
                        Button("Ignorer") { queue.ignore(job.id) }
                        Button("Remplacer…") { queue.confirmReplacement(job.id) }
                    }
                    Spacer(minLength: 0)
                    Button { queue.removeIntervention(job.id) } label: {
                        Image(systemName: "trash").frame(width: 20, height: 18)
                    }
                    .help("Retirer cette tâche de la file sans supprimer ses fichiers")
                    .accessibilityLabel("Supprimer la tâche de la file")
                }
                .buttonStyle(.borderless)
                .disabled(queue.activeID == job.id)
            }
        }
    }

    private func manualDraft(_ job: MovieJob) -> Binding<ManualMetadataDraft> {
        Binding(get: { manualDrafts[job.id] ?? ManualMetadataDraft(job: job) },
                set: { manualDrafts[job.id] = $0 })
    }

    @ViewBuilder private func metadataWarning(_ job: MovieJob) -> some View {
        if let warning = job.metadataWarning {
            Label(warning, systemImage: "exclamationmark.triangle")
                .font(.caption).foregroundStyle(Color.orange)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Button("Ajouter…", systemImage: "plus") { queue.addMovies() }
                    .buttonStyle(.borderless)
                    .foregroundStyle(Color.accentColor)
                    .fontWeight(.medium)
                Spacer(minLength: 0)
                Button(queue.settings.paused ? "Démarrer" : "Pause", systemImage: queue.settings.paused ? "play.fill" : "pause") { queue.togglePause() }
                    .buttonStyle(.borderless)
                    .help(queue.settings.paused ? "Reprendre la file" : "Pause après le film en cours, sans interrompre Subler")
            }
            HStack(spacing: 8) {
                Button { queue.openSource() } label: {
                    Image(systemName: "folder").frame(width: 20, height: 18)
                }.help("Ouvrir le dossier source").accessibilityLabel("Ouvrir le dossier source")
                Button { queue.openLogs() } label: {
                    Image(systemName: "doc.text").frame(width: 20, height: 18)
                }.help("Voir les journaux").accessibilityLabel("Voir les journaux")
                Button {
                    // Invoke the scene and its focus request in the same action.
                    // A simultaneous TapGesture is not a native button action
                    // (keyboard/accessibility activation need not deliver it).
                    openSettings()
                    SettingsWindowFocus.request()
                } label: {
                    Label("Réglages…", systemImage: "gearshape")
                }.help("Ouvrir les réglages")
                Spacer(minLength: 0)
                Button { queue.quit() } label: { Image(systemName: "power").frame(width: 20, height: 18) }
                    .help("Quitter Subler Automation").accessibilityLabel("Quitter")
                    .keyboardShortcut("q")
            }
            .buttonStyle(.borderless)
        }
        .controlSize(.regular)
    }

    // System colours keep the same hierarchy in light, dark and increased-contrast appearances.
    private func card<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content().frame(maxWidth: .infinity, alignment: .leading).padding(12)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.quaternary, lineWidth: 1))
    }

    private var interventions: [MovieJob] {
        queue.jobs.filter { $0.needsSelection || [.failed, .paused, .waitingForServer].contains($0.status) }
    }
    private var statusTitle: String {
        if !queue.permissions.state.isReady { return "Autorisations" }
        if queue.message != nil { return "À vérifier" }
        if queue.currentJob != nil { return "En cours" }
        if queue.settings.paused { return "En pause" }
        return interventions.isEmpty ? "Prêt" : "À vérifier"
    }
    private var statusSymbol: String {
        if queue.message != nil { return "exclamationmark.circle.fill" }
        if queue.currentJob != nil { return "circle.inset.filled" }
        if queue.settings.paused { return "pause.fill" }
        return interventions.isEmpty ? "checkmark.circle" : "exclamationmark.circle.fill"
    }
    private var statusColor: Color {
        if queue.message != nil { return .orange }
        if queue.currentJob != nil { return .accentColor }
        if queue.settings.paused || !interventions.isEmpty { return .orange }
        return .secondary
    }
    private func candidateRows(_ choices: [MetadataCandidate], for job: MovieJob) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Confirmer les métadonnées").font(.caption).bold()
            Text("Plusieurs films possibles : choisissez le bon titre et l’année.")
                .font(.caption).foregroundStyle(.secondary)
            VStack(spacing: 4) {
                    ForEach(choices) { choice in
                        Button { queue.select(choice, for: job.id) } label: {
                            HStack(spacing: 8) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(choice.title).font(.subheadline).lineLimit(2)
                                    Text(String(choice.year)).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 4)
                                Image(systemName: "checkmark.circle").foregroundStyle(Color.accentColor)
                            }
                            .padding(8).frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(RoundedRectangle(cornerRadius: 8))
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("Choisir \(choice.title), \(choice.year)")
                        .disabled(queue.activeID == job.id)
                    }
            }
        }
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
