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
    init() {
        InstanceLock.acquire()
        _queue = StateObject(wrappedValue: JobQueueService())
        NSApplication.shared.setActivationPolicy(.accessory)
    }
    var body: some Scene {
        MenuBarExtra("Subler Automation", systemImage: queue.symbol) { MenuBarView(queue: queue) }
            .menuBarExtraStyle(.window)
        Settings { SettingsView(queue: queue) }
    }
}
