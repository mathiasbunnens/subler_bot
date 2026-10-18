import SwiftUI
import AppKit
import UniformTypeIdentifiers
import AutomationCore

/// Deliberately independent of the watched/SMB queue and of Subler's shared queue.
@MainActor
final class AppleTVPreparationModel: ObservableObject {
    static let shared = AppleTVPreparationModel()
    @Published private(set) var source: URL?
    @Published private(set) var media: AppleTVMedia?
    @Published private(set) var result: URL?
    @Published private(set) var status = "Choisissez un MKV ou MP4 à analyser."
    @Published private(set) var fraction = 0.0
    @Published private(set) var isBusy = false
    @Published var mode: AppleTVMode = .preserve { didSet { acknowledged = false; allowDynamicHDRLoss = false } }
    @Published var allowTrackLoss = false { didSet { acknowledged = false } }
    @Published var allowDynamicHDRLoss = false { didSet { acknowledged = false } }
    @Published var acknowledged = false
    private var task: Task<Void, Never>?

    var plan: AppleTVPlan? {
        guard let media else { return nil }
        return try? AppleTVPlan.make(media: media, mode: mode, allowTrackLoss: allowTrackLoss, allowDynamicHDRLoss: allowDynamicHDRLoss)
    }
    var planDescription: String {
        guard let media else { return "" }
        do { return try AppleTVPlan.make(media: media, mode: mode, allowTrackLoss: allowTrackLoss, allowDynamicHDRLoss: allowDynamicHDRLoss).summary }
        catch { return error.localizedDescription }
    }
    func chooseSource() {
        guard !isBusy else { return }
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.message = "Analyse seule : aucun film n’est ajouté à la file automatique."
        if panel.runModal() == .OK, let url = panel.url { analyze(url) }
    }
    func analyze(_ url: URL) {
        guard !isBusy else { return }
        source = url; media = nil; result = nil; acknowledged = false; allowDynamicHDRLoss = false
        status = "Analyse ffprobe…"; fraction = 0; isBusy = true
        task = Task {
            defer { isBusy = false; task = nil }
            do {
                media = try await AppleTVPreparationService.inspect(source: url)
                try Task.checkCancellation()
                status = "Analyse terminée. Vérifiez le diagnostic et le compromis avant de préparer."
            } catch is CancellationError { media = nil; status = "Analyse annulée." }
            catch { media = nil; status = safeMessage(error) }
        }
    }
    func chooseDestination() {
        guard !isBusy, plan != nil, acknowledged, let source else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.mpeg4Movie]
        panel.nameFieldStringValue = source.deletingPathExtension().lastPathComponent + ".AppleTV.mp4"
        panel.message = "Disque local uniquement. Aucun fichier existant ne sera remplacé."
        guard panel.runModal() == .OK, let destination = panel.url else { return }
        start(destination: destination)
    }
    func start(destination: URL) {
        guard !isBusy, plan != nil, acknowledged, let source else { return }
        let selectedMode = mode, trackLoss = allowTrackLoss, dynamicLoss = allowDynamicHDRLoss
        isBusy = true; fraction = 0; result = nil
        status = selectedMode == .preserve ? "Remux sans réencodage vidéo…" : "Encodage vidéo VideoToolbox…"
        task = Task {
            defer { isBusy = false; task = nil }
            do {
                result = try await AppleTVPreparationService.prepare(source: source, destination: destination,
                    mode: selectedMode, allowTrackLoss: trackLoss, allowDynamicHDRLoss: dynamicLoss) { [weak self = self] value in
                        Task { @MainActor [weak self] in
                            guard let self, self.isBusy, Int(value * 100) != Int(self.fraction * 100) else { return }
                            self.fraction = value
                            if value >= 0.97 { self.status = "Vérification du décodage QuickTime…" }
                        }
                    }
                fraction = 1
                status = "MP4 créé ; images décodées par AVFoundation. À vérifier sur votre Apple TV réelle."
            } catch is CancellationError { status = "Annulé ; aucun résultat partiel publié. Original conservé." }
            catch { status = safeMessage(error) }
        }
    }
    func cancel() { status = "Annulation et nettoyage…"; task?.cancel() }
    func cancelAndWait() async {
        let active = task
        active?.cancel()
        await active?.value
    }
    private func safeMessage(_ error: Error) -> String {
        (error as? AutomationServiceError)?.localizedDescription ?? "Échec de préparation ou accès disque refusé. Aucun original n’est modifié."
    }
}

struct AppleTVPreparationView: View {
    @ObservedObject private var model = AppleTVPreparationModel.shared
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Un MP4 autonome pour QuickTime et Apple TV").font(.headline)
                Text("Outil manuel indépendant : ne modifie ni la file Subler ni le transfert SMB. L’original n’est jamais écrasé.")
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    Button("Choisir un fichier…") { model.chooseSource() }.disabled(model.isBusy)
                    if let source = model.source { Text(source.lastPathComponent).lineLimit(1).truncationMode(.middle) }
                }
                Picker("Vidéo", selection: $model.mode) {
                    ForEach(AppleTVMode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }.disabled(model.isBusy)
                Text("Copie sans perte par défaut si compatible. H.264 SDR ≤1080p30 ou HEVC Main 10 HDR10 matériel avec perte pour Apple TV 4K. HDR10 : BT.2020/PQ limité et mastering/CLL requis, résolution/cadence inchangées ; aucun tone mapping. HLG et Dolby Vision sans base HDR10 8.1 validée sont refusés.")
                    .font(.caption).foregroundStyle(.secondary)
                if let media = model.media {
                    DisclosureGroup("Diagnostic des pistes") {
                        Text(media.diagnostic).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    Toggle("Autoriser l’exclusion des sous-titres et pièces jointes", isOn: $model.allowTrackLoss)
                        .disabled(model.isBusy)
                    if model.mode == .hdr10 {
                        Toggle("J’accepte le réencodage avec perte et la suppression de Dolby Vision / HDR10+ dynamiques si présents (HDR10 statique uniquement)", isOn: $model.allowDynamicHDRLoss)
                            .disabled(model.isBusy)
                    }
                    Text(model.planDescription).font(.caption).fixedSize(horizontal: false, vertical: true)
                    Toggle("J’accepte le compromis décrit (audio AAC stéréo si nécessaire)", isOn: $model.acknowledged)
                        .disabled(model.isBusy || model.plan == nil)
                    Button("Préparer le MP4…") { model.chooseDestination() }
                        .foregroundStyle(Color.accentColor)
                        .disabled(model.isBusy || model.plan == nil || !model.acknowledged)
                }
                if model.isBusy {
                    ProgressView(value: model.fraction)
                    Button("Annuler") { model.cancel() }
                }
                Text(model.status).font(.caption).textSelection(.enabled)
                if let result = model.result {
                    Button("Afficher le MP4 dans le Finder") { NSWorkspace.shared.activateFileViewerSelecting([result]) }
                }
                Text("FFmpeg + ffprobe : brew install ffmpeg. Cache exclusif surveillé (budget 64 Gio) sur le disque de sortie, nettoyé après succès/annulation. Après interruption brutale : recommencer, jamais reprendre un fichier partiel.")
                    .font(.caption2).foregroundStyle(.secondary)
            }.padding(16)
        }.buttonStyle(.borderless)
    }
}
