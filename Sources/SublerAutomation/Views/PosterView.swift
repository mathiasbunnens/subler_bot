import SwiftUI
import AppKit

/// Cover of the film being sent to the server. Loads off the main thread and
/// falls back to a neutral placeholder when the MP4 had no artwork or the file
/// cannot be decoded. Callers key it by job identity so a new film never shows
/// the previous film's poster while its own image loads.
struct PosterView: View {
    let path: String?
    @State private var image: NSImage?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6).fill(.quaternary)
            if let image {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
            } else {
                Image(systemName: "film").font(.title2).foregroundStyle(.secondary)
            }
        }
        .frame(width: 64, height: 96)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.quaternary, lineWidth: 1))
        .accessibilityLabel(image == nil ? "Affiche indisponible" : "Affiche du film")
        .task(id: path) {
            image = nil
            guard let path else { return }
            let loaded = await Task.detached(priority: .utility) { NSImage(contentsOfFile: path) }.value
            if !Task.isCancelled { image = loaded }
        }
    }
}
