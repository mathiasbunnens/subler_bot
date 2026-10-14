import AppKit
import SwiftUI
import AutomationCore

/// Real scene and real native Settings control, not direct focus-helper calls.
@MainActor enum PresentationSettingsClick {
    static func prepare() {
        setbuf(stdout, nil)
        let root = ProcessInfo.processInfo.environment["SUBLER_AUTOMATION_TEST_ROOT"]!
        precondition(root.hasPrefix(NSHomeDirectory() + "/.hermes/cache/scratch/"))
        var settings = AppSettings()
        settings.sourcePath = root + "/Source"; settings.temporaryPath = root + "/Temp"
        settings.paused = true; settings.watchFolder = false; settings.notifications = false
        settings.presentationMode = ProcessInfo.processInfo.environment["PRESENTATION_INITIAL_MODE"] == "normal" ? .normal : .menuBar
        try! settings.save()
    }
    static func settle() async { try? await Task.sleep(nanoseconds: 600_000_000) }
    static func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
    static func host(_ queue: JobQueueService) async -> NSWindow {
        if queue.settings.presentationMode == .normal {
            AppPresentationController.shared.showMainWindow()
            await settle()
            return AppPresentationController.shared.mainWindow!
        }
        if let popup = NSApp.windows.first(where: { $0.isVisible && String(describing: type(of: $0)).contains("MenuBarExtra") }) { return popup }
        NSApp.activate(ignoringOtherApps: true)
        await settle()
        let status = NSApp.windows.first { String(describing: type(of: $0)) == "NSStatusBarWindow" && !$0.title.isEmpty }!
        descendants(status.contentView!).compactMap { $0 as? NSStatusBarButton }.first!.performClick(nil)
        await settle()
        guard let popup = NSApp.windows.first(where: { $0.isVisible && String(describing: type(of: $0)).contains("MenuBarExtra") }) else {
            if !NSApp.isActive {
                print("EXTERNAL_FOCUS_INTERRUPTED: inactive app while opening native popup")
                exit(2)
            }
            preconditionFailure("Native popup did not open in active app")
        }
        return popup
    }
    static func settingsWindows() -> [NSWindow] {
        NSApp.windows.filter { $0.contentView != nil && abs($0.contentView!.bounds.width - 590) < 1 }
    }
    static func run(_ queue: JobQueueService) async {
        await settle()
        let mode = queue.settings.presentationMode.rawValue
        precondition(queue.settings.paused && queue.activeID == nil && queue.permissions.state.isReady)
        var exact: NSWindow?
        for step in 0..<5 {
            if let exact {
                if step == 1 || step == 4 { exact.orderOut(nil) }
                if step == 2 { exact.close() }
            }
            NSApp.activate(ignoringOtherApps: true)
            let source = await host(queue)
            source.makeKeyAndOrderFront(nil)
            await settle()
            let buttons = descendants(source.contentView!).compactMap { $0 as? NSButton }
            print("BUTTONS: \(buttons.map { "\($0.title)|\($0.accessibilityLabel() ?? "")" })")
            // SwiftUI labels are hosted subviews, not NSButton.title. With this
            // idle fixture the native footer is Add, Pause, Source, Logs, Settings, Quit.
            precondition(buttons.count == 6, "Unexpected idle footer controls")
            let button = buttons[4]
            if step == 3 {
                guard let competitor = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.Terminal").first else { preconditionFailure("Terminal focus competitor unavailable") }
                // macOS may refuse a programmatic activation: that is an environment
                // limit of this step, not a Settings focus failure.
                guard competitor.activate(options: [.activateIgnoringOtherApps]) else {
                    print("EXTERNAL_FOCUS_INTERRUPTED: Terminal refused programmatic activation"); exit(2)
                }
                await settle()
                guard !NSApp.isActive else {
                    print("EXTERNAL_FOCUS_INTERRUPTED: competing app did not take focus"); exit(2)
                }
                print("EXTERNAL_FOCUS_PRECONDITION: \(NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "unknown")")
            }
            button.performClick(nil)
            await settle()
            // Workspace frontmost can lag AppKit's key/active notifications.
            // Observe convergence only; do not activate again or mask the action.
            for _ in 0..<5 {
                if NSWorkspace.shared.frontmostApplication?.processIdentifier == ProcessInfo.processInfo.processIdentifier { break }
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
            let windows = settingsWindows()
            precondition(windows.count == 1, "Must reuse exactly one Settings scene window")
            let settings = windows[0]
            if let exact { precondition(settings === exact, "Settings window identity changed") }
            else { exact = settings }
            print("SETTINGS_CLICK \(mode) step=\(step): visible=\(settings.isVisible) key=\(settings.isKeyWindow) active=\(NSApp.isActive) count=\(windows.count) frontmost=\(NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "unknown")")
            if !NSApp.isActive && step != 3 {
                print("EXTERNAL_FOCUS_INTERRUPTED: discarded inactive test app; not a key-window failure")
                exit(2)
            }
            precondition(settings.isVisible && settings.isKeyWindow && NSApp.isActive, "Actual Settings click did not bring exact host forward")
            precondition(NSWorkspace.shared.frontmostApplication?.processIdentifier == ProcessInfo.processInfo.processIdentifier, "Settings app is not actually frontmost")
        }
        print("PRESENTATION_SETTINGS_CLICK_PASS: \(mode) initial, hidden, closed, repeated, rehidden; exact native scene identity and key window")
        exit(0)
    }
}
