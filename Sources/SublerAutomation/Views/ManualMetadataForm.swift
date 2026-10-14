import SwiftUI
import AutomationCore

struct ManualMetadataDraft {
    var expanded = false
    var title: String
    var year: String
    var error: String?
    init(job: MovieJob) {
        title = job.manualMetadata?.title ?? job.title ?? ""
        year = (job.manualMetadata?.year ?? job.year).map(String.init) ?? ""
    }
}

struct ManualMetadataForm: View {
    @ObservedObject var queue: JobQueueService
    let job: MovieJob
    @Binding var draft: ManualMetadataDraft

    var body: some View {
        DisclosureGroup("Saisir le titre et l’année manuellement", isExpanded: $draft.expanded) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Requis : titre du film et année de sortie. Les autres informations (affiche, résumé, acteurs) restent facultatives. La conversion et la vérification du MP4 restent obligatoires.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                TextField("Titre du film (obligatoire)", text: $draft.title)
                    .accessibilityLabel("Titre du film")
                TextField("Année de sortie (4 chiffres)", text: $draft.year)
                    .accessibilityLabel("Année de sortie")
                if let error = draft.error {
                    Text(error).font(.caption).foregroundStyle(Color.red)
                        .fixedSize(horizontal: false, vertical: true).accessibilityLabel("Erreur de saisie : \(error)")
                }
                Button("Appliquer et reprendre la conversion") {
                    draft.error = queue.applyManualMetadata(title: draft.title, year: draft.year, for: job.id)
                }
                .buttonStyle(.borderless).foregroundStyle(Color.accentColor)
                .disabled(queue.activeID == job.id)
            }.padding(.top, 6)
        }
        .disabled(queue.activeID == job.id)
    }
}
