import AppKit
import SwiftUI
import AutomationCore

/// Compile with the real queue/settings/views in a scratch Swift package.
/// The launcher must set a fresh SUBLER_AUTOMATION_TEST_ROOT; no production state.
@main
struct UILayoutSmoke {
    @MainActor static func main() {
        setbuf(stdout, nil)
        NSApplication.shared.setActivationPolicy(.accessory)
        Task { @MainActor in
            do {
                try await runChecks()
                exit(0)
            } catch {
                print("UI_LAYOUT_SMOKE_ERROR: \(error)")
                exit(1)
            }
        }
        NSApplication.shared.run()
    }

    @MainActor static func runChecks() async throws {
        guard let rootPath = ProcessInfo.processInfo.environment["SUBLER_AUTOMATION_TEST_ROOT"],
              rootPath.hasPrefix(NSHomeDirectory() + "/.hermes/cache/scratch/") else {
            fatalError("Requires an isolated Hermes scratch test root")
        }
        let root = URL(fileURLWithPath: rootPath)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        var configuration = AppSettings()
        configuration.sourcePath = root.appendingPathComponent("Source").path
        configuration.temporaryPath = root.appendingPathComponent("Temp").path
        configuration.paused = true; configuration.watchFolder = false; configuration.notifications = false
        try configuration.save()

        let queue = JobQueueService()
        queue.settings.paused = false // No watched sources/jobs; fixture jobs are paused, never transferable.
        let host = NSHostingView(rootView: MenuBarView(queue: queue))
        let menu = NSWindow(contentRect: NSRect(x: 200, y: 200, width: 380, height: 600),
                            styleMask: [.titled, .closable], backing: .buffered, defer: false)
        menu.title = "Subler UI test — isolated"
        menu.contentView = host
        menu.orderFront(nil)
        defer { menu.orderOut(nil) }

        func pump() async { try? await Task.sleep(nanoseconds: 500_000_000) }
        func settle() async {
            await pump()
            menu.setContentSize(host.fittingSize)
            host.layoutSubtreeIfNeeded()
            await pump()
            menu.setContentSize(host.fittingSize)
            host.layoutSubtreeIfNeeded()
        }
        func scrollViews(_ view: NSView) -> [NSScrollView] {
            (view as? NSScrollView).map { [$0] } ?? view.subviews.flatMap(scrollViews)
        }
        func assertUnclipped(_ label: String) {
            let scrolls = scrollViews(host)
            print("UI_LAYOUT: \(label) scrolls=\(scrolls.count) intrinsicHeight=\(host.fittingSize.height) actualHeight=\(host.bounds.height)")
            precondition(scrolls.isEmpty, "Short content must size naturally without a scroll viewport")
            precondition(abs(host.fittingSize.height - host.bounds.height) <= 2, "Unexpected empty reserved height")
        }
        await settle()
        assertUnclipped("idle")
        var job = MovieJob(sourcePath: root.appendingPathComponent("Synthetic.2001.mkv").path, fingerprint: "synthetic")
        job.status = .paused; job.error = "Confirmez le titre du film."; job.needsSelection = true
        queue.jobs = [job]
        queue.candidates[job.id] = [MetadataCandidate(index: 1, title: "Synthetic", year: 2001, raw: "Movie: Synthetic (2001)")]
        await settle()
        assertUnclipped("one intervention")
        queue.candidates[job.id] = (1...30).map { MetadataCandidate(index: $0, title: "Synthetic candidate \($0)", year: 2001, raw: "fixture \($0)") }
        await settle()
        let scrolls = scrollViews(host)
        precondition(scrolls.count == 1, "Nested miniature candidate scroll")
        precondition(scrolls[0].contentView.bounds.height <= 461, "Unbounded menu content")
        precondition((scrolls[0].documentView?.frame.height ?? 0) > scrolls[0].contentView.bounds.height, "Long candidate list must scroll")
        print("UI_LAYOUT: long candidate list uses one bounded scroll")

        let fixture = URL(fileURLWithPath: job.sourcePath)
        let original = Data("Synthetic source, never converted".utf8)
        try original.write(to: fixture)
        let local = root.appendingPathComponent("Temp/preserved.mp4")
        let outputBytes = Data("Synthetic local output, never transferred".utf8)
        try outputBytes.write(to: local)
        job.localPath = local.path
        var completed = MovieJob(sourcePath: root.appendingPathComponent("Completed.mkv").path, fingerprint: "completed")
        completed.status = .completed
        queue.jobs = [job, completed]
        let confirmation = Timer(timeInterval: 0.1, repeats: false) { _ in
            NSApplication.shared.stopModal(withCode: .alertSecondButtonReturn)
        }
        RunLoop.main.add(confirmation, forMode: .modalPanel)
        queue.removeIntervention(job.id)
        confirmation.invalidate()
        precondition(queue.jobs.map(\.id) == [completed.id], "Confirmed removal did not remove only its job")
        precondition(queue.candidates[job.id] == nil, "Removed task retained metadata choices")
        precondition(queue.message == nil, "Successful removal must not leave a false À vérifier error")
        let sourceAfter = try Data(contentsOf: fixture), outputAfter = try Data(contentsOf: local)
        precondition(sourceAfter == original, "Source was modified by task removal")
        precondition(outputAfter == outputBytes, "Local output was modified by task removal")
        let persisted = try QueueStore(root: root)
        let savedIDs = try persisted.load().map(\.id)
        let dismissed = try persisted.isDismissed(fingerprint: FileIdentity.fingerprint(fixture))
        precondition(savedIDs == [completed.id], "Removal did not persist")
        precondition(dismissed, "Watcher dismissal did not persist")
        print("UI_REMOVAL: native confirmation, queue/persistence, candidate cleanup, source/output preserved")

        queue.settings.paused = true
        var missing = MovieJob(sourcePath: root.appendingPathComponent("Missing.Spider-Man.mkv").path, fingerprint: "missing-spider-man")
        missing.needsSelection = true
        queue.jobs = [missing, completed]
        queue.candidates[missing.id] = [MetadataCandidate(index: 1, title: "Spider-Man", year: 2026, raw: "fixture")]
        queue.retry(missing.id)
        precondition(queue.jobs.first?.status == .failed, "Retry silently returned missing source to pending")
        precondition(queue.jobs.first?.error?.contains("source") == true, "Missing-source retry needs an actionable explanation")
        precondition(queue.jobs.first?.needsSelection == false && queue.candidates[missing.id] == nil, "Missing source retained stale metadata controls")
        precondition(queue.activeID == nil, "Missing-source retry started Subler")
        let missingConfirmation = Timer(timeInterval: 0.1, repeats: false) { _ in
            NSApplication.shared.stopModal(withCode: .alertSecondButtonReturn)
        }
        RunLoop.main.add(missingConfirmation, forMode: .modalPanel)
        queue.removeIntervention(missing.id)
        missingConfirmation.invalidate()
        precondition(queue.jobs.map(\.id) == [completed.id], "Missing-source intervention cannot be removed")
        let missingSavedIDs = try persisted.load().map(\.id)
        precondition(missingSavedIDs == [completed.id], "Missing-source removal did not survive persistence")
        let missingDismissed = try persisted.isDismissed(fingerprint: missing.fingerprint)
        precondition(missingDismissed, "Missing-source original fingerprint not retained for suppression")
        precondition(!FileManager.default.fileExists(atPath: missing.sourcePath), "Removal recreated missing source")
        let restoredSource = URL(fileURLWithPath: missing.sourcePath)
        try Data("Restored fixture; paused and never imported".utf8).write(to: restoredSource)
        queue.jobs = [missing, completed]
        queue.retry(missing.id)
        precondition(queue.jobs.first?.status == .pending && queue.jobs.first?.error == nil && queue.jobs.first?.needsSelection == false, "Retry cannot recover after the source is restored")
        precondition(queue.activeID == nil, "Paused restored-source retry started Subler")
        queue.jobs = [completed]
        let preservedOutput = try Data(contentsOf: local)
        precondition(preservedOutput == outputBytes, "Missing-source removal altered another output")
        queue.settings.paused = false
        print("UI_MISSING_SOURCE: actionable retry, restored-source retry, native removal and reopened persistence; completed history/output preserved")

        var permissionRequests: [Bool] = []
        let deniedPermissions = PermissionPreparationService(operations: .init(
            automation: { request in permissionRequests.append(request); return .denied },
            sourceRead: { _, _ in nil }, temporaryWrite: { _, _ in nil }, mountedShare: { _ in nil },
            networkRead: { _, _ in nil }, notifications: { _ in .granted }, load: { nil }, save: { _ in }))
        let gatedQueue = JobQueueService(permissions: deniedPermissions)
        gatedQueue.settings.watchFolder = true; gatedQueue.settings.paused = false
        let unscanned = URL(fileURLWithPath: gatedQueue.settings.sourcePath).appendingPathComponent("Must.Not.Start.mkv")
        try Data("No native Subler call is allowed".utf8).write(to: unscanned)
        await pump()
        await gatedQueue.tick()
        await gatedQueue.tick()
        precondition(gatedQueue.activeID == nil, "Denied permissions started a worker")
        precondition(!gatedQueue.jobs.contains { $0.sourcePath == unscanned.path }, "Denied permissions allowed folder scanning")
        precondition(permissionRequests == [true], "Ticks repeated the permission request")
        precondition(!deniedPermissions.state.isReady, "Denied permission marked ready")
        print("UI_PERMISSION_GATE: denied startup blocks scanning/work; repeated ticks never repeat a prompt")

        let controller = AppPresentationController.shared
        controller.bind(queue)
        await pump()
        controller.apply(.normal)
        await pump()
        guard let mainHost = controller.mainWindow?.contentView as? NSHostingView<MenuBarView> else {
            preconditionFailure("Normal app mode did not create the real main view")
        }
        print("UI_NORMAL_WINDOW: intrinsicHeight=\(mainHost.fittingSize.height) actualHeight=\(mainHost.bounds.height)")
        precondition(abs(mainHost.fittingSize.height - mainHost.bounds.height) <= 2, "Normal window reserves transparent empty height")
        controller.apply(.menuBar)
        if ProcessInfo.processInfo.environment["SUBLER_UI_LAYOUT_ONLY"] == "1" {
            print("UI_LAYOUT_ONLY_PASS: layout, removal and main window; foreground checks explicitly skipped")
            return
        }

        let settings = NSWindow(contentRect: NSRect(x: 300, y: 250, width: 590, height: 540),
                                styleMask: [.titled, .closable], backing: .buffered, defer: false)
        settings.title = "Subler settings test — isolated"
        settings.contentView = NSHostingView(rootView: SettingsView(queue: queue))
        settings.orderFront(nil)
        settings.contentView?.layoutSubtreeIfNeeded()
        func awaitSettingsFocus(_ label: String) async {
            for attempt in 1...6 {
                await pump()
                if settings.isVisible && settings.isKeyWindow && NSApplication.shared.isActive {
                    print("SETTINGS_FOCUS: \(label) visible=true key=true active=true")
                    return
                }
                // Do not mistake another application stealing activation for our
                // window ordering bug. An active fixture with the wrong key window fails.
                precondition(!NSApplication.shared.isActive, "Settings was not key while the fixture remained active")
                let external = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "unknown"
                print("SETTINGS_EXTERNAL_INTERRUPTION: \(external), discarded attempt \(attempt)")
                SettingsWindowFocus.request()
            }
            preconditionFailure("Settings focus was externally blocked after bounded retries")
        }
        await awaitSettingsFocus("initial")
        settings.orderOut(nil)
        menu.makeKeyAndOrderFront(nil)
        SettingsWindowFocus.request()
        await awaitSettingsFocus("repeated")
        settings.orderOut(nil)
        print("UI_LAYOUT_SMOKE_PASS: idle/intervention sizing, bounded single scroll, initial and repeated settings focus")
    }
}
