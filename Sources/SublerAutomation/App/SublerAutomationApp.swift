import SwiftUI
import AutomationCore
import AppKit
import Darwin

private enum InstanceLock {
    static var descriptor: Int32 = -1
    static func acquire() {
        let root = AppSettings.file.deletingLastPathComponent()
        do { try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true) }
        catch { return } // Queue initialization will surface this failure without processing.
        descriptor = open(root.appendingPathComponent("instance.lock").path, O_CREAT | O_RDWR, 0o600)
        guard descriptor >= 0, flock(descriptor, LOCK_EX | LOCK_NB) == 0 else { exit(0) }
    }
}

@main
struct SublerAutomationApp: App {
    @StateObject private var queue: JobQueueService
    @NSApplicationDelegateAdaptor(AppPresentationDelegate.self) private var appDelegate
    init() {
        InstanceLock.acquire()
        let queue = JobQueueService()
        _queue = StateObject(wrappedValue: queue)
        NSApplication.shared.setActivationPolicy(queue.settings.presentationMode == .normal ? .regular : .accessory)
        AppPresentationController.shared.bind(queue)
    }
    var body: some Scene {
        MenuBarExtra(isInserted: Binding(
            get: { queue.settings.presentationMode == .menuBar },
            set: { _ in } // Insertion is derived only from validated, saved settings.
        )) { MenuBarView(queue: queue) } label: { MenuBarStatusLabel(queue: queue) }
            .menuBarExtraStyle(.window)
        Settings { SettingsView(queue: queue) }
    }
}
