import AppKit
import Combine
import SwiftUI
import AutomationCore

/// Owns an actual native main window, sharing the same live queue as the menu.
@MainActor
final class AppPresentationController {
    static let shared = AppPresentationController()
    private(set) var mainWindow: NSWindow?
    private(set) var mode: AppPresentationMode = .menuBar
    private weak var queue: JobQueueService?
    private var settingsObserver: AnyCancellable?
    private var dockBadgeObserver: AnyCancellable?

    func bind(_ queue: JobQueueService) {
        self.queue = queue
        dockBadgeObserver = queue.$jobs.combineLatest(queue.$settings)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] jobs, settings in
                self?.updateDockBadge(jobs: jobs, mode: settings.presentationMode)
            }
        settingsObserver = queue.$settings.map(\.presentationMode).removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] mode in self?.apply(mode) }
    }

    func updateDockBadge(jobs: [MovieJob], mode: AppPresentationMode) {
        let decoration = QueueStatusDecoration.resolve(jobs: jobs, currentJob: nil,
            message: nil, hasCompletedThisSession: false)
        NSApp.dockTile.badgeLabel = mode == .normal ? decoration.dockBadgeLabel : nil
    }

    func apply(_ mode: AppPresentationMode) {
        // Saving Settings must not replace its focus with the main host or lose it
        // when accessory activation and status-item removal change window ordering.
        let focusedWindow = NSApplication.shared.keyWindow
        self.mode = mode
        NSApplication.shared.setActivationPolicy(mode == .normal ? .regular : .accessory)
        if mode == .normal { showMainWindow() }
        else { mainWindow?.orderOut(nil) }
        if let focusedWindow, focusedWindow !== mainWindow, focusedWindow.isVisible {
            NSApplication.shared.activate(ignoringOtherApps: true)
            focusedWindow.makeKeyAndOrderFront(nil)
            SettingsWindowFocus.restore(if: focusedWindow)
        }
    }

    func showMainWindow() {
        guard mode == .normal, let queue else { return }
        if mainWindow == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 420, height: 640),
                                  styleMask: [.titled, .closable, .miniaturizable, .resizable],
                                  backing: .buffered, defer: false)
            window.title = "Subler Automation"
            window.identifier = NSUserInterfaceItemIdentifier("SublerAutomation.MainWindow")
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: MenuBarView(queue: queue))
            window.center()
            mainWindow = window
        }
        guard let window = mainWindow else { return }
        if window.isMiniaturized { window.deminiaturize(nil) }
        NSApplication.shared.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
}

@MainActor
final class AppPresentationDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        FinderServiceProvider.shared.register()
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        AppPresentationController.shared.showMainWindow()
        return true
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}
