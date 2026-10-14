import AppKit
import SwiftUI
import AutomationCore

/// Compiled beside a scratch copy of the real @main entrypoint. No substitute App/Scene.
@MainActor enum PresentationEntrypointSmoke {
    static func prepare() {
        setbuf(stdout, nil)
        let root = ProcessInfo.processInfo.environment["SUBLER_AUTOMATION_TEST_ROOT"]!
        precondition(root.hasPrefix(NSHomeDirectory() + "/.hermes/cache/scratch/"))
        var settings = AppSettings()
        // Layout fixtures model a configured server (no "Serveur non configuré" card).
        settings.smb = SMBConfiguration(serverURL: "smb://fixture.invalid/Movies", username: "fixture", expectedMountPath: "/Volumes/Fixture")
        settings.sourcePath = root + "/Source"
        settings.temporaryPath = root + "/Temp"
        settings.paused = true; settings.watchFolder = false; settings.notifications = false
        settings.presentationMode = ProcessInfo.processInfo.environment["PRESENTATION_INITIAL_MODE"] == "normal" ? .normal : .menuBar
        try! settings.save()
        var job = MovieJob(sourcePath: root + "/retained-synthetic.mkv", fingerprint: "presentation-fixture")
        job.status = .completed
        try! QueueStore(root: URL(fileURLWithPath: root)).save([job])
    }
    static func settle() async { try? await Task.sleep(nanoseconds: 800_000_000) }
    static func statusWindows() -> [NSWindow] {
        // AppKit's installed status-item windows, not the SwiftUI insertion request.
        // SwiftUI's named Item-N host survives removal (isVisible can stay true);
        // its untitled native menu-bar mirror is what is actually inserted/removed.
        NSApp.windows.filter { window in
            String(describing: type(of: window)) == "NSStatusBarWindow" &&
            window.title.isEmpty && window.isVisible
        }
    }
    static func assertMode(_ mode: AppPresentationMode) {
        let controller = AppPresentationController.shared
        let items = statusWindows()
        print("MODE \(mode.rawValue): policy=\(NSApp.activationPolicy().rawValue) statusItems=\(items.count) mainVisible=\(controller.mainWindow?.isVisible ?? false)")
        print("OWNED WINDOWS: \(NSApp.windows.map { "\(type(of: $0)): \($0.title), visible=\($0.isVisible), frame=\($0.frame), alpha=\($0.alphaValue), level=\($0.level.rawValue)" })")
        precondition(NSApp.activationPolicy() == (mode == .normal ? .regular : .accessory))
        precondition(items.count == (mode == .menuBar ? 1 : 0), "Exclusive mode must create/remove the actual native menu-bar mirror")
        precondition((controller.mainWindow?.isVisible ?? false) == (mode == .normal))
    }
    static func run(_ queue: JobQueueService) async {
        await settle()
        let initial = queue.settings.presentationMode
        assertMode(initial)
        let controller = AppPresentationController.shared
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let jobs = try! encoder.encode(queue.jobs)
        let original = queue.settings
        // A real settings host remains alive, with its draft/view identity, while modes switch.
        let settings = NSWindow(contentRect: NSRect(x: 200, y: 200, width: 590, height: 540), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        settings.isReleasedWhenClosed = false
        settings.contentView = NSHostingView(rootView: SettingsView(queue: queue))
        settings.makeKeyAndOrderFront(nil)
        await settle()
        let settingsView = settings.contentView
        var main: NSWindow?
        for mode: AppPresentationMode in [.normal, .menuBar, .normal, .menuBar] {
            var next = original; next.presentationMode = mode
            queue.applySettings(next)
            await settle()
            assertMode(mode)
            precondition((try! encoder.encode(queue.jobs)) == jobs && queue.settings == next && (try! AppSettings.load()) == next, "Mode switching must retain queue and persisted settings")
            precondition(settings.isVisible && settings.contentView === settingsView, "Switch must retain settings window/view")
            precondition(settings.isKeyWindow && NSApp.isActive, "Saving presentation from Settings must retain Settings focus")
            if mode == .normal {
                if let main { precondition(controller.mainWindow === main, "Reuse main host") }
                main = controller.mainWindow
            }
        }
        settings.orderOut(nil)
        var normal = original; normal.presentationMode = .normal
        queue.applySettings(normal)
        await settle()
        precondition(controller.mainWindow?.isKeyWindow == true)
        let skipMiniaturization = ProcessInfo.processInfo.environment["PRESENTATION_SKIP_MINIATURIZATION"] == "1"
        let delegate = AppPresentationDelegate()
        if skipMiniaturization {
            print("MINIATURIZATION_EXPLICITLY_SKIPPED: environment-controlled check, no system preference changes")
        } else {
        print("MINIMIZE_BEFORE: style=\(controller.mainWindow!.styleMask.rawValue) miniaturizable=\(controller.mainWindow!.styleMask.contains(.miniaturizable)) frontmost=\(NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "unknown")")
        let observed = controller.mainWindow!
        let tokens = [NSWindow.willMiniaturizeNotification, NSWindow.didMiniaturizeNotification, NSWindow.didDeminiaturizeNotification].map { name in
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { note in
                print("MINIMIZE_NOTIFICATION: \(note.name.rawValue) main=\((note.object as? NSWindow) === observed)")
            }
        }
        print("MINIMIZE_CAPABILITY: button=\(observed.standardWindowButton(.miniaturizeButton)?.isEnabled ?? false) options=\(NSApp.presentationOptions.rawValue) delegate=\(String(describing: observed.delegate)) appDelegate=\(String(describing: NSApp.delegate))")
        controller.mainWindow?.miniaturize(nil)
        defer { tokens.forEach(NotificationCenter.default.removeObserver) }
        for _ in 0..<10 {
            if controller.mainWindow?.isMiniaturized == true { break }
            await settle()
        }
        print("MINIMIZE_AFTER: minimized=\(controller.mainWindow!.isMiniaturized) visible=\(controller.mainWindow!.isVisible) active=\(NSApp.isActive)")
        precondition(controller.mainWindow?.isMiniaturized == true)
        _ = delegate.applicationShouldHandleReopen(NSApp, hasVisibleWindows: true)
        await settle()
        precondition(controller.mainWindow?.isMiniaturized == false && controller.mainWindow?.isKeyWindow == true)
        }
        controller.mainWindow?.close()
        _ = delegate.applicationShouldHandleReopen(NSApp, hasVisibleWindows: false)
        await settle()
        precondition(controller.mainWindow === main && main?.isVisible == true && main?.isKeyWindow == true)
        var menu = normal; menu.presentationMode = .menuBar
        queue.applySettings(menu)
        await settle()
        _ = delegate.applicationShouldHandleReopen(NSApp, hasVisibleWindows: false)
        await settle()
        assertMode(.menuBar)
        print("PRESENTATION_ENTRYPOINT_PASS: \(initial.rawValue) startup, actual status removal/insertion, repeated switching, state/settings identity+focus, closed Dock reopen, accessory reopen guard; miniaturizationChecked=\(!skipMiniaturization)")
        exit(0)
    }
}
