import AppKit
import AutomationCore

/// Finder → clic droit → Services → « Envoyer au serveur avec Subler Automation ».
/// Declared in Info.plist (NSServices). Received films go through the normal
/// queue (`enqueue`), never through a separate copy path: an MKV is always
/// converted and validated before any SMB transfer.
@MainActor
final class FinderServiceProvider: NSObject {
    static let shared = FinderServiceProvider()
    weak var queue: JobQueueService?

    func register() {
        NSApplication.shared.servicesProvider = self
        NSUpdateDynamicServices()
    }

    @objc func sendMoviesToServer(_ pasteboard: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        let urls = (pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]) ?? []
        guard let queue else {
            error.pointee = "Subler Automation n’est pas prêt." as NSString
            return
        }
        let result = FinderSubmission.partition(urls)
        let before = queue.jobs.count
        queue.enqueue(result.accepted)
        let added = queue.jobs.count - before
        let text = FinderSubmission.summary(result, added: added)
        if added == 0 {
            // Nothing entered the queue: explain why instead of failing silently.
            let alert = NSAlert()
            alert.messageText = "Aucun film ajouté"
            alert.informativeText = text + (queue.message.map { "\n\n\($0)" } ?? "")
            NSApplication.shared.activate(ignoringOtherApps: true)
            alert.runModal()
            return
        }
        queue.announce(text)
        Task { await queue.tick() }
    }
}
