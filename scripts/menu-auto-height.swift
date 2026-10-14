import AppKit
import SwiftUI
import AutomationCore

/// Stand-in whose class name matches the real popup ("MenuBarExtraWindow") so
/// the production auto-sizer acts on it. Off-screen, never activated.
final class FakeMenuBarExtraWindow: NSWindow {}

// Background check of the popup auto-height: an oversized popup window (the
// empty band the user saw) must shrink to the real content height, keep its
// top edge, then follow content growth and shrinkage.
@main struct MenuAutoHeight {
    @MainActor static func main() {
        setbuf(stdout, nil)
        let root = URL(fileURLWithPath: ProcessInfo.processInfo.environment["SUBLER_AUTOMATION_TEST_ROOT"]!)
        precondition(root.path.hasPrefix(NSHomeDirectory() + "/.hermes/cache/scratch/"))
        var settings = AppSettings()
        settings.sourcePath = root.appendingPathComponent("Source").path
        settings.temporaryPath = root.appendingPathComponent("Temp").path
        settings.watchFolder = false; settings.notifications = false; settings.paused = true
        try! settings.save()
        try! QueueStore(root: root).save([])
        NSApplication.shared.setActivationPolicy(.prohibited)
        let queue = JobQueueService()
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 800_000_000)
            let top: CGFloat = -19000
            let window = FakeMenuBarExtraWindow(contentRect: NSRect(x: -20000, y: top - 900, width: 380, height: 900),
                                                styleMask: [.borderless], backing: .buffered, defer: false)
            let host = NSHostingView(rootView: MenuBarView(queue: queue))
            // Simulate the stuck real popup: the hosting view no longer drives the
            // window size, so only the production auto-sizer can fit it.
            host.sizingOptions = []
            window.contentView = host
            window.orderBack(nil)
            func settle() async { try? await Task.sleep(nanoseconds: 500_000_000) }
            func check(_ step: String) {
                let fitting = NSHostingView(rootView: MenuBarView(queue: queue)).fittingSize.height
                print("AUTO_HEIGHT \(step): window=\(window.frame.height) content=\(fitting) top=\(window.frame.maxY)")
                precondition(abs(window.frame.height - fitting) < 1.5, "\(step): window \(window.frame.height) != content \(fitting)")
                precondition(abs(window.frame.maxY - top) < 0.5, "\(step): top edge moved")
            }
            await settle(); check("oversized idle shrinks")
            var job = MovieJob(sourcePath: "/fixture/a.mkv", fingerprint: "a")
            job.status = .failed; job.error = String(repeating: "Erreur longue de test. ", count: 12)
            var second = MovieJob(sourcePath: "/fixture/b.mkv", fingerprint: "b")
            second.status = .paused; second.needsSelection = true
            queue.jobs = [job, second]
            await settle(); check("grows with interventions")
            queue.jobs = []
            await settle(); check("shrinks back to idle")
            print("MENU_AUTO_HEIGHT_PASS")
            exit(0)
        }
        NSApplication.shared.run()
    }
}
