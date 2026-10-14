import AppKit
import SwiftUI
import AutomationCore

@main struct ManualMetadataQueueSmoke {
    @MainActor static func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
    @MainActor static func main() {
        setbuf(stdout, nil)
        let root = URL(fileURLWithPath: ProcessInfo.processInfo.environment["SUBLER_AUTOMATION_TEST_ROOT"]!)
        precondition(root.path.hasPrefix(NSHomeDirectory() + "/.hermes/cache/scratch/"))
        var settings = AppSettings()
        settings.sourcePath = root.appendingPathComponent("Source").path
        settings.temporaryPath = root.appendingPathComponent("Temp").path
        settings.watchFolder = false; settings.notifications = false; settings.paused = true
        try! settings.save()
        let source = root.appendingPathComponent("synthetic.mkv")
        try! Data("synthetic inactive input".utf8).write(to: source)
        var job = MovieJob(sourcePath: source.path, fingerprint: try! FileIdentity.fingerprint(source))
        job.status = .paused; job.needsSelection = true
        let store = try! QueueStore(root: root)
        try! store.save([job])
        let application = NSApplication.shared
        application.setActivationPolicy(.accessory)
        let queue = JobQueueService()
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 500_000_000)
            precondition(queue.settings.paused && !queue.settings.watchFolder && !queue.settings.notifications && queue.activeID == nil)
            let before = try! Data(contentsOf: root.appendingPathComponent("jobs.json"))
            precondition(queue.applyManualMetadata(title: "", year: "2024", for: job.id) != nil)
            precondition((try! Data(contentsOf: root.appendingPathComponent("jobs.json"))) == before)
            queue.activeID = job.id
            precondition(queue.applyManualMetadata(title: "Test", year: "2024", for: job.id) != nil)
            queue.activeID = nil
            let host = NSHostingView(rootView: MenuBarView(queue: queue))
            let fitting = host.fittingSize
            precondition(fitting.width > 0 && fitting.height > 0)
            print("RENDERED_MENU_FITTING: \(fitting)")
            var draft = ManualMetadataDraft(job: job)
            draft.expanded = true
            let form = NSHostingView(rootView: ManualMetadataForm(queue: queue, job: job, draft: Binding(get: { draft }, set: { draft = $0 })).frame(width: 360))
            let window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 380, height: 280), styleMask: [.titled, .closable], backing: .buffered, defer: false)
            window.contentView = form
            // Off-screen and never activated: the smoke must not cover the user's desktop.
            window.setFrameOrigin(NSPoint(x: -20000, y: -20000))
            window.orderBack(nil)
            try? await Task.sleep(nanoseconds: 300_000_000)
            let fields = descendants(form).compactMap { $0 as? NSTextField }.filter { $0.isEditable }
            let buttons = descendants(form).compactMap { $0 as? NSButton }
            print("FORM_BUTTONS: \(buttons.map { "title=\($0.title) label=\($0.accessibilityLabel() ?? "")" }) FIELDS: \(fields.count)")
            precondition(buttons.count == 1, "Expected exactly the owned form's apply button")
            let apply = buttons[0]
            precondition(fields.count == 2 && !apply.isBordered)
            apply.performClick(nil)
            precondition(draft.error != nil && queue.jobs[0].needsSelection)
            fields[0].stringValue = "  L’été du test  "
            fields[0].delegate?.controlTextDidChange?(Notification(name: NSControl.textDidChangeNotification, object: fields[0]))
            fields[1].stringValue = "2024"
            fields[1].delegate?.controlTextDidChange?(Notification(name: NSControl.textDidChangeNotification, object: fields[1]))
            precondition(draft.title == "  L’été du test  " && draft.year == "2024")
            apply.performClick(nil)
            precondition(draft.error == nil)
            window.orderOut(nil)
            let loaded = try! store.load()[0]
            precondition(loaded.manualMetadata?.title == "L’été du test" && loaded.title == "L’été du test" && loaded.year == 2024)
            precondition(loaded.candidateIndex == nil && loaded.candidateRaw == nil && !loaded.validated && loaded.validatedDigest == nil)
            precondition(loaded.status == .pending && loaded.metadataWarning != nil)
            try? await Task.sleep(nanoseconds: 200_000_000)
            precondition(queue.activeID == nil && queue.jobs[0].status == .pending)
            // Recreate an inactive intervention and prove missing source remains a visible failure.
            queue.jobs[0].status = .paused; queue.jobs[0].needsSelection = true
            try! store.save(queue.jobs)
            try! FileManager.default.removeItem(at: source)
            precondition(queue.applyManualMetadata(title: "Changed", year: "2025", for: job.id) != nil)
            precondition(queue.jobs[0].status == .failed && queue.jobs[0].error?.contains("introuvable") == true)
            // A malformed persistence target must return an error and retain the global processing gate.
            try! Data("restored synthetic input".utf8).write(to: source)
            let state = root.appendingPathComponent("jobs.json")
            try! FileManager.default.moveItem(at: state, to: root.appendingPathComponent("jobs-preserved.json"))
            try! FileManager.default.createDirectory(at: state, withIntermediateDirectories: false)
            precondition(queue.applyManualMetadata(title: "Cannot persist", year: "2026", for: job.id) != nil)
            precondition(queue.settings.paused && queue.message?.contains("Sauvegarde impossible") == true)
            print("MANUAL_METADATA_QUEUE_PASS: native editable fields and apply button, form validation error, active guard, real SwiftUI host, durable identity, paused restart gate, missing source, persistence failure; no Subler Apple Events or transfer")
            exit(0)
        }
        application.run()
    }
}
