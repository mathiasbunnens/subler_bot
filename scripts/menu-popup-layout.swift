import AppKit
import SwiftUI
import AutomationCore

/// Uses the actual App/Scene and real queue removal; no window sizing intervention.
@MainActor enum MenuPopupLayout {
    static func prepare() {
        setbuf(stdout, nil)
        let root = ProcessInfo.processInfo.environment["SUBLER_AUTOMATION_TEST_ROOT"]!
        precondition(root.hasPrefix(NSHomeDirectory() + "/.hermes/cache/scratch/"))
        var settings = AppSettings()
        settings.sourcePath = root + "/Source"; settings.temporaryPath = root + "/Temp"
        settings.paused = true; settings.watchFolder = false; settings.notifications = false
        settings.presentationMode = .menuBar
        try! settings.save()
    }
    static func settle() async { try? await Task.sleep(nanoseconds: 350_000_000) }
    static func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
    static func openMenu() async -> NSWindow {
        guard let status = NSApp.windows.first(where: { String(describing: type(of: $0)) == "NSStatusBarWindow" && $0.title.isEmpty && $0.isVisible }),
              let content = status.contentView else { preconditionFailure("Native status item missing") }
        print("STATUS VIEWS: \(descendants(content).map { String(describing: type(of: $0)) })")
        let host = NSApp.windows.first { String(describing: type(of: $0)) == "NSStatusBarWindow" && !$0.title.isEmpty }!
        print("HOST VIEWS: \(descendants(host.contentView!).map { "\(type(of: $0)) \($0.frame)" })")
        guard let button = descendants(host.contentView!).compactMap({ $0 as? NSStatusBarButton }).first else { preconditionFailure("Native status button missing") }
        NSApp.activate(ignoringOtherApps: true)
        await settle()
        button.performClick(nil)
        await settle()
        print("WINDOWS: \(NSApp.windows.map { "\(type(of: $0)) visible=\($0.isVisible) frame=\($0.frame)" })")
        guard let popup = NSApp.windows.first(where: { $0.isVisible && String(describing: type(of: $0)).contains("MenuBarExtra") }) else { preconditionFailure("Real MenuBarExtra popup did not open") }
        return popup
    }
    static func inspect(_ popup: NSWindow, _ label: String, long: Bool, queue: JobQueueService) -> CGFloat {
        precondition(popup.isVisible, "Native popup unexpectedly closed")
        let content = popup.contentView!
        let views = descendants(content)
        let scrolls = views.compactMap { $0 as? NSScrollView }
        let height = content.bounds.height
        print("POPUP \(label): window=\(popup.frame) actual=\(height) scrolls=\(scrolls.count)")
        let buttons = views.compactMap { $0 as? NSButton }
        precondition(!buttons.isEmpty && buttons.allSatisfy { !$0.isBordered }, "Native menu buttons must remain transparent")
        if long {
            precondition(scrolls.count == 1, "Long content must have one scroll only")
            precondition(scrolls[0].contentView.bounds.height <= 461, "Long content must be bounded")
            precondition((scrolls[0].documentView?.frame.height ?? 0) > scrolls[0].contentView.bounds.height, "Long content must remain scrollable")
        } else {
            precondition(scrolls.isEmpty, "Short native content retains a scroll viewport")
            // Independent ideal-size oracle only; it never owns or resizes the popup.
            let ideal = NSHostingView(rootView: MenuBarView(queue: queue)).fittingSize.height
            print("IDEAL \(label): \(ideal)")
            precondition(abs(height - ideal) <= 2, "Native popup retains empty reserved height")
        }
        return height
    }
    static func run(_ queue: JobQueueService) async {
        let observer = NotificationCenter.default.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main) { _ in
            print("EXTERNAL_ACTIVATION: \(NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "unknown")")
        }
        defer { NotificationCenter.default.removeObserver(observer) }
        await settle()
        precondition(queue.settings.paused && queue.activeID == nil && queue.permissions.state.isReady)
        let root = URL(fileURLWithPath: ProcessInfo.processInfo.environment["SUBLER_AUTOMATION_TEST_ROOT"]!)
        var job = MovieJob(sourcePath: root.appendingPathComponent("Synthetic.Spider-Man.mkv").path, fingerprint: "popup-fixture")
        job.status = .paused; job.needsSelection = true; job.error = "Confirmez le titre."
        try! Data("Preserved synthetic source".utf8).write(to: URL(fileURLWithPath: job.sourcePath))
        queue.jobs = [job]
        queue.candidates[job.id] = (1...30).map { MetadataCandidate(index: $0, title: "Synthetic candidate \($0)", year: 2001, raw: "fixture \($0)") }
        await settle()
        let popup = await openMenu()
        let longHeight = inspect(popup, "long", long: true, queue: queue)
        queue.candidates[job.id] = [MetadataCandidate(index: 1, title: "Synthetic", year: 2001, raw: "fixture")]
        await settle()
        let shortHeight = inspect(popup, "short", long: false, queue: queue)
        precondition(shortHeight < longHeight - 30, "Actual MenuBarExtra did not shrink after long content")
        // Grow again, then remove directly from the scrolling state (no intermediate short layout).
        queue.candidates[job.id] = (1...30).map { MetadataCandidate(index: $0, title: "Synthetic candidate \($0)", year: 2001, raw: "fixture \($0)") }
        await settle()
        _ = inspect(popup, "regrown before removal", long: true, queue: queue)
        // Cancel through the same native trash callback. Nothing, including the
        // scroll branch or persisted queue, may change when the modal is cancelled.
        let store = try! QueueStore(root: root)
        try! store.save(queue.jobs)
        let beforeCancel = try! Data(contentsOf: root.appendingPathComponent("jobs.json"))
        let cancellation = Timer(timeInterval: 0.15, repeats: false) { _ in
            guard let modal = NSApp.modalWindow, let content = modal.contentView,
                  let cancel = descendants(content).compactMap({ $0 as? NSButton }).first(where: { $0.title == "Annuler" }) else { preconditionFailure("Native cancel missing") }
            cancel.performClick(nil)
        }
        RunLoop.main.add(cancellation, forMode: .modalPanel)
        let cancelDocument = descendants(popup.contentView!).compactMap({ $0 as? NSScrollView }).first!.documentView!
        let cancelTrash = descendants(cancelDocument).compactMap({ $0 as? NSButton }).last!
        precondition(cancelTrash.bounds.width == 20 && cancelTrash.bounds.height == 18)
        cancelDocument.scrollToVisible(cancelTrash.convert(cancelTrash.bounds, to: cancelDocument))
        cancelTrash.performClick(nil)
        cancellation.invalidate()
        await settle()
        let cancelledPopup = popup.isVisible ? popup : await openMenu()
        precondition(queue.jobs.count == 1 && queue.jobs[0].id == job.id && queue.candidates[job.id]?.count == 30)
        precondition((try! Data(contentsOf: root.appendingPathComponent("jobs.json"))) == beforeCancel)
        precondition(abs(inspect(cancelledPopup, "cancelled long removal", long: true, queue: queue) - longHeight) <= 2)
        // Remove a second, tall intervention so one short intervention remains:
        // this crosses the scroll threshold without relying on the idle branch.
        queue.candidates[job.id] = [MetadataCandidate(index: 1, title: "Synthetic", year: 2001, raw: "fixture")]
        var second = MovieJob(sourcePath: root.appendingPathComponent("Second.mkv").path, fingerprint: "second")
        second.status = .paused; second.needsSelection = true
        try! Data("Second retained source".utf8).write(to: URL(fileURLWithPath: second.sourcePath))
        queue.jobs.append(second)
        queue.candidates[second.id] = (1...30).map { MetadataCandidate(index: $0, title: "Second candidate \($0)", year: 2001, raw: "fixture") }
        await settle()
        _ = inspect(cancelledPopup, "two interventions before threshold removal", long: true, queue: queue)
        let thresholdConfirmation = Timer(timeInterval: 0.15, repeats: false) { _ in
            let content = NSApp.modalWindow!.contentView!
            descendants(content).compactMap({ $0 as? NSButton }).first(where: { $0.title == "Supprimer de la liste" })!.performClick(nil)
        }
        RunLoop.main.add(thresholdConfirmation, forMode: .modalPanel)
        let thresholdDocument = descendants(cancelledPopup.contentView!).compactMap({ $0 as? NSScrollView }).first!.documentView!
        let thresholdTrash = descendants(thresholdDocument).compactMap({ $0 as? NSButton }).last!
        precondition(thresholdTrash.bounds.width == 20 && thresholdTrash.bounds.height == 18)
        thresholdDocument.scrollToVisible(thresholdTrash.convert(thresholdTrash.bounds, to: thresholdDocument))
        thresholdTrash.performClick(nil)
        thresholdConfirmation.invalidate()
        await settle()
        let thresholdPopup = cancelledPopup.isVisible ? cancelledPopup : await openMenu()
        precondition(queue.jobs.count == 1 && queue.jobs[0].id == job.id && queue.candidates[second.id] == nil)
        precondition(abs(inspect(thresholdPopup, "confirmed removal below scroll threshold", long: false, queue: queue) - shortHeight) <= 2)
        precondition((try! store.load()).count == 1)
        precondition((try! Data(contentsOf: URL(fileURLWithPath: second.sourcePath))) == Data("Second retained source".utf8))
        queue.candidates[job.id] = (1...30).map { MetadataCandidate(index: $0, title: "Synthetic candidate \($0)", year: 2001, raw: "fixture") }
        await settle()
        _ = inspect(thresholdPopup, "regrown for last removal", long: true, queue: queue)
        let confirmation = Timer(timeInterval: 0.15, repeats: false) { _ in
            guard let modal = NSApp.modalWindow, let content = modal.contentView,
                  let confirm = descendants(content).compactMap({ $0 as? NSButton }).first(where: { $0.title == "Supprimer de la liste" }) else { preconditionFailure("Native removal confirmation missing") }
            confirm.performClick(nil)
        }
        RunLoop.main.add(confirmation, forMode: .modalPanel)
        guard let document = descendants(thresholdPopup.contentView!).compactMap({ $0 as? NSScrollView }).first?.documentView,
              let trash = descendants(document).compactMap({ $0 as? NSButton }).last else { preconditionFailure("Native intervention removal button missing") }
        // The intervention's last native button is its trash control, after candidates/retry.
        precondition(trash.bounds.width == 20 && trash.bounds.height == 18)
        document.scrollToVisible(trash.convert(trash.bounds, to: document))
        trash.performClick(nil)
        confirmation.invalidate()
        await settle()
        precondition(queue.jobs.isEmpty && queue.candidates[job.id] == nil && queue.activeID == nil)
        // A modal alert may dismiss the menu. Reopen through the status item, never resize.
        let idlePopup = thresholdPopup.isVisible ? thresholdPopup : await openMenu()
        let idleHeight = inspect(idlePopup, "idle after native removal", long: false, queue: queue)
        precondition(idleHeight < shortHeight - 60, "Last intervention removal did not shrink actual popup")
        precondition((try! QueueStore(root: root).load()).isEmpty)
        precondition((try! Data(contentsOf: URL(fileURLWithPath: job.sourcePath))) == Data("Preserved synthetic source".utf8))
        print("MENU_POPUP_LAYOUT_PASS: native long→short→regrown→cancel→two interventions→confirmed threshold crossing→regrown→last removal→idle; persistence/source preserved; no manual resizing")
        exit(0)
    }
}
