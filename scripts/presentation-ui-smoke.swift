import AppKit
import SwiftUI
import AutomationCore

@main struct PresentationUISmoke {
    @MainActor static func main() {
        setbuf(stdout, nil)
        NSApplication.shared.setActivationPolicy(.accessory)
        Task { @MainActor in
            await checks()
            exit(0)
        }
        NSApplication.shared.run()
    }
    @MainActor static func checks() async {
        var resignCount = 0
        let observer = NotificationCenter.default.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main) { _ in
            resignCount += 1
            print("RESIGN: frontmost=\(NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "nil") pid=\(NSWorkspace.shared.frontmostApplication?.processIdentifier ?? 0)")
        }
        defer { NotificationCenter.default.removeObserver(observer) }
        let root = ProcessInfo.processInfo.environment["SUBLER_AUTOMATION_TEST_ROOT"]!
        precondition(root.hasPrefix(NSHomeDirectory() + "/.hermes/cache/scratch/"))
        var config = AppSettings()
        config.sourcePath = root + "/Source"; config.temporaryPath = root + "/Temp"
        config.watchFolder = false; config.paused = true; config.notifications = false
        try! config.save()
        let queue = JobQueueService()
        let menu = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 380, height: 500), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        menu.contentView = NSHostingView(rootView: Text("Isolated menu focus competitor"))
        let settings = NSWindow(contentRect: NSRect(x: 200, y: 200, width: 590, height: 540), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        settings.contentView = NSHostingView(rootView: SettingsView(queue: queue))
        settings.orderFront(nil)
        settings.contentView?.layoutSubtreeIfNeeded()
        try? await Task.sleep(nanoseconds: 500_000_000)
        var accepted = 0
        var attempts = 0
        while accepted < 20 && attempts < 80 {
            attempts += 1
            let previousResignCount = resignCount
            settings.orderOut(nil)
            menu.makeKeyAndOrderFront(nil)
            SettingsWindowFocus.request()
            // Simulate the menu's deferred focus handoff after a SettingsLink click.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { menu.makeKeyAndOrderFront(nil) }
            try? await Task.sleep(nanoseconds: 500_000_000)
            if resignCount != previousResignCount {
                print("FOCUS_INTERFERENCE: another app activated; discard attempt \(attempts)")
                continue
            }
            print("FOCUS \(accepted): visible=\(settings.isVisible) key=\(settings.isKeyWindow) active=\(NSApp.isActive)")
            precondition(settings.isVisible && settings.isKeyWindow && NSApp.isActive, "Repeated request failed at \(accepted)")
            accepted += 1
        }
        precondition(accepted == 20, "Could not obtain 20 uncontended focus checks; stop other desktop UI tests")
        settings.miniaturize(nil)
        try? await Task.sleep(nanoseconds: 200_000_000)
        SettingsWindowFocus.request()
        try? await Task.sleep(nanoseconds: 300_000_000)
        precondition(!settings.isMiniaturized && settings.isVisible && settings.isKeyWindow, "Settings request must restore minimized window")
        settings.orderOut(nil); menu.orderOut(nil)
        #if !FOCUS_ONLY
        let controller = AppPresentationController.shared
        controller.bind(queue)
        try? await Task.sleep(nanoseconds: 200_000_000)
        precondition(NSApp.activationPolicy() == .accessory && controller.mainWindow == nil)
        config.presentationMode = .normal
        queue.applySettings(config)
        try? await Task.sleep(nanoseconds: 300_000_000)
        precondition(queue.settings.presentationMode == .normal)
        precondition(NSApp.activationPolicy() == .regular && NSRunningApplication.current.activationPolicy == .regular)
        precondition(controller.mainWindow?.isVisible == true && controller.mainWindow?.isKeyWindow == true)
        controller.mainWindow?.close()
        let delegate = AppPresentationDelegate()
        _ = delegate.applicationShouldHandleReopen(NSApp, hasVisibleWindows: false)
        precondition(controller.mainWindow?.isVisible == true)
        var invalid = config
        invalid.presentationMode = .menuBar; invalid.sourcePath = "relative/invalid"
        queue.applySettings(invalid)
        try? await Task.sleep(nanoseconds: 200_000_000)
        precondition(queue.settings.presentationMode == .normal && NSApp.activationPolicy() == .regular, "Invalid save changed presentation")
        config.presentationMode = .menuBar
        queue.applySettings(config)
        try? await Task.sleep(nanoseconds: 200_000_000)
        precondition(NSApp.activationPolicy() == .accessory && controller.mainWindow?.isVisible == false)

        var completed = MovieJob(sourcePath: root + "/synthetic.mkv", fingerprint: "fixture")
        completed.status = .completed
        precondition(!MenuBarStatusImage.isFinished(jobs: [completed], currentJob: nil, message: nil), "No completion badge on startup from history")
        precondition(MenuBarStatusImage.isFinished(jobs: [completed], currentJob: nil, message: nil, hasCompletedThisSession: true))
        precondition(!MenuBarStatusImage.isFinished(jobs: [], currentJob: nil, message: nil))
        precondition(!MenuBarStatusImage.isFinished(jobs: [completed], currentJob: completed, message: nil))
        precondition(!MenuBarStatusImage.isFinished(jobs: [completed], currentJob: nil, message: "error"))
        for status in JobStatus.allCases where status != .completed {
            var other = completed; other.status = status
            precondition(!MenuBarStatusImage.isFinished(jobs: [completed, other], currentJob: nil, message: nil, hasCompletedThisSession: true), "Badge for \(status)")
        }
        completed.error = "failure"
        precondition(!MenuBarStatusImage.isFinished(jobs: [completed], currentJob: nil, message: nil))
        completed.error = nil; completed.needsSelection = true
        precondition(!MenuBarStatusImage.isFinished(jobs: [completed], currentJob: nil, message: nil))
        let icon = MenuBarStatusImage.image(symbol: "film", finished: true, dark: false)
        precondition(!icon.isTemplate)
        let bitmap = NSBitmapImageRep(data: icon.tiffRepresentation!)!
        var greenCount = 0
        var greenInTopLeft = 0
        for y in 0..<bitmap.pixelsHigh { for x in 0..<bitmap.pixelsWide {
            let color = bitmap.colorAt(x: x, y: y)!.usingColorSpace(.deviceRGB)!
            if color.alphaComponent > 0.2 && color.greenComponent > color.redComponent + 0.08 && color.greenComponent > color.blueComponent + 0.08 {
                greenCount += 1
                if x < bitmap.pixelsWide / 2 && y < bitmap.pixelsHigh / 2 { greenInTopLeft += 1 }
            }
        }}
        print("BADGE: green pixels=\(greenCount), top-left=\(greenInTopLeft), bitmap=\(bitmap.pixelsWide)x\(bitmap.pixelsHigh)")
        precondition(greenCount > 0 && greenInTopLeft == greenCount, "Green badge must be top-left")
        print("PRESENTATION_UI_PASS: 20 deferred handoffs + minimized settings, real regular/accessory mode, close/reopen, rejected save, all badge statuses, green top-left pixels")
        #else
        print("PRESENTATION_UI_PASS: 20 repeated settings requests with deferred menu focus handoffs, minimized window restored")
        #endif
    }
}
