import AppKit
import SwiftUI
import AutomationCore

// Off-screen render of the real menu and Settings views to PNG files, for visual
// review without showing any window on the user's desktop. Launched with
// `open -g` (never activated) by scripts/render-ui.py.
@main struct RenderUI {
    @MainActor static func render<V: View>(_ view: V, size: NSSize, appearance: NSAppearance.Name, to url: URL, settle: UInt64 = 300_000_000) async {
        let host = NSHostingView(rootView: view)
        let window = NSWindow(contentRect: NSRect(origin: NSPoint(x: -20000, y: -20000), size: size),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: appearance)
        window.contentView = host
        host.frame = NSRect(origin: .zero, size: size)
        let fitting = host.fittingSize
        let final = NSSize(width: size.width, height: max(fitting.height, 10))
        window.setContentSize(final); host.frame = NSRect(origin: .zero, size: final)
        window.orderBack(nil)
        // Let .task modifiers (poster loading) run before capturing.
        try? await Task.sleep(nanoseconds: settle)
        host.layoutSubtreeIfNeeded()
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { preconditionFailure("no bitmap") }
        host.cacheDisplay(in: host.bounds, to: rep)
        try! rep.representation(using: .png, properties: [:])!.write(to: url)
        window.orderOut(nil)
        print("RENDERED \(url.lastPathComponent) \(Int(final.width))x\(Int(final.height))")
    }

    @MainActor static func main() {
        setbuf(stdout, nil)
        let root = URL(fileURLWithPath: ProcessInfo.processInfo.environment["SUBLER_AUTOMATION_TEST_ROOT"]!)
        precondition(root.path.hasPrefix(NSHomeDirectory() + "/.hermes/cache/scratch/"))
        let out = URL(fileURLWithPath: ProcessInfo.processInfo.environment["RENDER_OUTPUT"]!)
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
            for name in [NSAppearance.Name.aqua, .darkAqua] {
                let suffix = name == .aqua ? "light" : "dark"
                queue.jobs = []; queue.activeID = nil; queue.progress = nil
                await render(MenuBarView(queue: queue), size: NSSize(width: 380, height: 600), appearance: name, to: out.appendingPathComponent("menu-idle-\(suffix).png"))

                // Transfer with poster.
                var sending = MovieJob(sourcePath: "/fixture/Dune.mkv", fingerprint: "a")
                sending.title = "Dune : Deuxième partie"; sending.year = 2024
                sending.status = .transferring; sending.workRoot = root.path
                let posterFolder = root.appendingPathComponent(sending.id.uuidString)
                try? FileManager.default.createDirectory(at: posterFolder, withIntermediateDirectories: true)
                let poster = posterFolder.appendingPathComponent("poster.png")
                if let fixture = ProcessInfo.processInfo.environment["RENDER_POSTER"] {
                    try? FileManager.default.removeItem(at: poster)
                    try! FileManager.default.copyItem(at: URL(fileURLWithPath: fixture), to: poster)
                }
                sending.posterPath = poster.path
                var manual = MovieJob(sourcePath: "/fixture/inconnu.mkv", fingerprint: "b")
                manual.status = .paused; manual.needsSelection = true
                manual.error = "Aucune métadonnée trouvée. Vérifiez le nom du MKV et le fournisseur dans Subler."
                var done = MovieJob(sourcePath: "/fixture/old.mkv", fingerprint: "c"); done.status = .completed
                queue.jobs = [sending, manual, done]
                queue.activeID = sending.id
                await render(MenuBarView(queue: queue), size: NSSize(width: 380, height: 700), appearance: name, to: out.appendingPathComponent("menu-transfer-\(suffix).png"), settle: 800_000_000)

                await render(SettingsView(queue: queue), size: NSSize(width: 590, height: 540), appearance: name, to: out.appendingPathComponent("settings-\(suffix).png"))
            }
            print("RENDER_UI_PASS")
            exit(0)
        }
        NSApplication.shared.run()
    }
}
