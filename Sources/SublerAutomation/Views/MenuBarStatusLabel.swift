import AppKit
import SwiftUI
import AutomationCore

enum MenuBarStatusImage {
    static func isFinished(jobs: [MovieJob], currentJob: MovieJob?, message: String?, hasCompletedThisSession: Bool = false) -> Bool {
        QueueStatusDecoration.resolve(jobs: jobs, currentJob: currentJob, message: message,
            hasCompletedThisSession: hasCompletedThisSession) == .finished
    }

    // AppKit image coordinates are unflipped: high y means TOP. Explicit top-left badge.
    static let badgeRect = MenuBarIconRenderer.badgeRect

    static func image(symbol: String, finished: Bool, dark: Bool, needsConfirmation: Bool = false) -> NSImage {
        let badge: (symbol: String, color: NSColor)?
        if needsConfirmation {
            badge = ("exclamationmark.triangle.fill", NSColor.systemOrange)
        } else if finished {
            badge = ("checkmark.circle.fill", NSColor.systemGreen)
        } else {
            badge = nil
        }
        // No opaque backdrop: the renderer clears a gap around the badge in the base glyph.
        let image = MenuBarIconRenderer.image(symbol: symbol, dark: dark, badge: badge)
        // A template image would erase the green when MenuBarExtra applies its tint.
        image.isTemplate = false
        image.accessibilityDescription = (needsConfirmation ? QueueStatusDecoration.metadataConfirmation :
            finished ? .finished : .none).accessibilityDescription
        return image
    }
}

struct MenuBarStatusLabel: View {
    @ObservedObject var queue: JobQueueService
    @Environment(\.colorScheme) private var colorScheme
    var body: some View {
        let decoration = QueueStatusDecoration.resolve(jobs: queue.jobs, currentJob: queue.currentJob,
            message: queue.message, hasCompletedThisSession: queue.hasCompletedThisSession)
        Image(nsImage: MenuBarStatusImage.image(symbol: queue.symbol,
            finished: decoration == .finished,
            dark: colorScheme == .dark, needsConfirmation: decoration == .metadataConfirmation))
            .accessibilityLabel(decoration.accessibilityDescription)
    }
}
