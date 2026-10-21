#!/usr/bin/env python3
"""Isolated AppKit/AE shutdown integration. No production engine/queue is launched.
The engine fixture retains the exact native shutdown handler, replacing only its
queue storage with generated in-memory records. Caller retains real app services;
only worker visibility is widened in the copied fixture source to inject a drain.
"""
from pathlib import Path
import json
import os
import plistlib
import shutil
import subprocess
import tempfile
import time

project = Path(__file__).resolve().parents[1]
scratch = Path.home() / '.hermes/profiles/codex-dev-2/cache/scratch'
root = Path(tempfile.mkdtemp(prefix='subler-shutdown-appkit-', dir=scratch))
print('EVIDENCE ' + str(root), flush=True)
env = dict(os.environ, TMPDIR=str(scratch))

def run(args, **kwargs):
    result = subprocess.run(list(map(str, args)), env=env, capture_output=True, text=True, timeout=180, **kwargs)
    if result.returncode:
        raise RuntimeError(result.stdout + result.stderr)
    return result.stdout

run(['swiftc', '-emit-library', '-emit-module', '-module-name', 'AutomationCore',
     *list((project / 'Sources/AutomationCore').glob('*.swift')),
     '-emit-module-path', root / 'AutomationCore.swiftmodule', '-o', root / 'libAutomationCore.dylib'])
source = (project / 'vendor-local/Subler/Classes/ScriptCommand.swift').read_text()
handler = source[source.index('enum BackgroundShutdownPolicy'):source.index('@objc(SBImportFileScriptCommand)')]
engine_source = '''import AppKit
class QueueItem: NSObject {
    enum Status { case completed }
    @objc let uniqueID = "foreign-fixture"
    let status: Status = .completed
}
class QueueController {
    static let shared = QueueController()
    enum Status { case idle, working }
    let status: Status = .idle
    var count: Int { mode == "foreignqueue" ? 1 : 0 }
    func items(at: IndexSet) -> [QueueItem] { count == 0 ? [] : [QueueItem()] }
}
let mode = (try? String(contentsOf: Bundle.main.resourceURL!.appendingPathComponent("mode"))) ?? "empty"
'''+handler+'''
let app = NSApplication.shared
app.setActivationPolicy(.prohibited)
if mode == "foreigndoc" { NSDocumentController.shared.addDocument(NSDocument()) }
// Self-cleanup only for generated fixture records, never a user process.
Timer.scheduledTimer(withTimeInterval: 15, repeats: false) { _ in exit(0) }
app.run()
'''
(root / 'engine.swift').write_text(engine_source)
run(['swiftc', root / 'engine.swift', '-o', root / 'Engine'])
caller = '''import AppKit
import AutomationCore
import Darwin
@main struct ShutdownFixture {
    @MainActor static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let delegate = AppPresentationDelegate()
        app.delegate = delegate
        let state = URL(fileURLWithPath: ProcessInfo.processInfo.environment["SUBLER_AUTOMATION_TEST_ROOT"]!)
        let mode = ProcessInfo.processInfo.environment["SHUTDOWN_MODE"]!
        let queue = JobQueueService()
        queue.settings.paused = true; queue.settings.watchFolder = false
        AppPresentationDelegate.queue = queue
        Task { @MainActor in
            do {
                // Let test-root permission startup finish without starting jobs.
                try await Task.sleep(nanoseconds: 100_000_000)
                let target = SublerTarget()
                if mode != "absent" { try await target.launchBackgroundIfNeeded() }
                let engine = NSRunningApplication.runningApplications(withBundleIdentifier: target.bundleIdentifier).first
                if let engine {
                    let expected = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/Subler Background.app").resolvingSymlinksInPath()
                    precondition(engine.bundleURL?.resolvingSymlinksInPath() == expected)
                    Task { @MainActor in
                        var samples = 0
                        while !engine.isTerminated {
                            precondition(!engine.isActive && NSWorkspace.shared.frontmostApplication?.processIdentifier != engine.processIdentifier,
                                         "Engine stole focus")
                            samples += 1
                            try! String(samples).write(to: state.appendingPathComponent("inactive-samples"), atomically: true, encoding: .utf8)
                            try? await Task.sleep(nanoseconds: 50_000_000)
                        }
                    }
                }
                try String(engine?.processIdentifier ?? 0).write(to: state.appendingPathComponent("engine.pid"), atomically: true, encoding: .utf8)
                queue.jobs = [MovieJob(sourcePath: state.appendingPathComponent("active.mkv").path, fingerprint: "fixture"),
                              MovieJob(sourcePath: state.appendingPathComponent("pending.mkv").path, fingerprint: "fixture-pending")]
                queue.worker = Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 700_000_000)
                    precondition(!Task.isCancelled, "Quit cancelled the owned worker")
                    queue.jobs[0].status = .paused
                    try! "finished".write(to: state.appendingPathComponent("worker-finished"), atomically: true, encoding: .utf8)
                }
                AppleTVPreparationModel.shared.task = Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 900_000_000)
                    precondition(!Task.isCancelled, "Quit cancelled manual preparation")
                    try! "finished".write(to: state.appendingPathComponent("manual-finished"), atomically: true, encoding: .utf8)
                }
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 200_000_000)
                    precondition(queue.isTerminating)
                    precondition(!FileManager.default.fileExists(atPath: state.appendingPathComponent("worker-finished").path))
                    if let engine { precondition(!engine.isTerminated, "Engine quit before drain finished") }
                    let late = state.appendingPathComponent("late.mkv")
                    try! Data("generated".utf8).write(to: late)
                    queue.enqueue([late])
                    precondition(queue.jobs.count == 2, "Quit admitted a new job")
                    try! "responsive".write(to: state.appendingPathComponent("main-responsive"), atomically: true, encoding: .utf8)
                    if mode == "repeated" { queue.quit() }
                }
                if mode == "signal" { kill(getpid(), SIGTERM) }
                else if mode == "native" {
                    RunLoop.main.perform { MainActor.assumeIsolated { app.terminate(nil) } }
                }
                else { queue.quit() }
            } catch {
                try? error.localizedDescription.write(to: state.appendingPathComponent("failure"), atomically: true, encoding: .utf8)
                exit(2)
            }
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + 25) {
            try? "fixture timeout".write(to: state.appendingPathComponent("failure"), atomically: true, encoding: .utf8)
            exit(3)
        }
        app.run()
        withExtendedLifetime(delegate) {}
    }
}
'''
(root / 'caller.swift').write_text(caller)
files = [root / 'caller.swift']
for folder in ['Views', 'Models', 'Services']:
    for path in (project / 'Sources/SublerAutomation' / folder).glob('*.swift'):
        if path.name == 'JobQueueService.swift':
            copy = root / path.name
            copy.write_text(path.read_text().replace('private var worker: Task<Void, Never>?', 'var worker: Task<Void, Never>?'))
            files.append(copy)
        elif path.name == 'AppleTVPreparationView.swift':
            copy = root / path.name
            copy.write_text(path.read_text().replace('private var task: Task<Void, Never>?', 'var task: Task<Void, Never>?'))
            files.append(copy)
        else:
            files.append(path)
run(['swiftc', '-parse-as-library', '-I', root, '-L', root, '-lAutomationCore',
     '-Xlinker', '-rpath', '-Xlinker', root, *files, '-o', root / 'Caller'])

def bundle(app, executable, info):
    macos = app / 'Contents/MacOS'
    macos.mkdir(parents=True)
    shutil.copy2(executable, macos / executable.name)
    (app / 'Contents/Info.plist').write_bytes(plistlib.dumps(dict(info, CFBundleExecutable=executable.name, CFBundlePackageType='APPL')))

results = []
# Only test-owned processes are launched; no application is addressed by bundle ID for quit.
for mode in ['absent', 'empty', 'native', 'signal', 'repeated', 'foreignqueue', 'foreigndoc', 'preexisting']:
    app = root / mode / 'Automation.app'
    engine = app / 'Contents/Helpers/Subler Background.app'
    bundle(engine, root / 'Engine', {'CFBundleIdentifier': 'local.sublerautomation.Subler',
        'LSBackgroundOnly': True, 'NSAppleScriptEnabled': True, 'OSAScriptingDefinition': 'Subler.sdef',
        'SublerAutomationBackgroundProtocol': '2', 'SublerAutomationGracefulQuitProtocol': '1'})
    resources = engine / 'Contents/Resources'
    resources.mkdir()
    (resources / 'Subler.sdef').write_text('''<?xml version="1.0"?><dictionary><suite name="Fixture" code="Subl" description="Scratch-only shutdown">
<command name="quit background if owned and idle" code="SublBgQt"><cocoa class="SBQuitBackgroundScriptCommand"/><direct-parameter type="text"/><result type="text"/></command>
</suite></dictionary>''')
    (resources / 'mode').write_text(mode)
    run(['codesign', '--force', '--sign', '-', engine])
    bundle(app, root / 'Caller', {'CFBundleIdentifier': 'local.sublerautomation.shutdown.' + mode,
        'LSUIElement': True, 'NSAppleEventsUsageDescription': 'Scratch-only embedded engine shutdown test',
        'SublerAutomationEngine': 'background', 'SublerAutomationBackgroundRelativePath': 'Contents/Helpers/Subler Background.app'})
    run(['codesign', '--force', '--sign', '-', app])
    if mode == 'preexisting':
        run(['open', '-g', '-n', engine])
        time.sleep(.5)
    state = root / mode / 'state'
    out, err = root / mode / 'stdout', root / mode / 'stderr'
    run(['open', '-g', '-n', '-W', '--stdout', out, '--stderr', err,
         '--env', 'SUBLER_AUTOMATION_TEST_ROOT=' + str(state), '--env', 'SHUTDOWN_MODE=' + mode, app])
    assert not (state / 'failure').exists(), (state / 'failure').read_text() if (state / 'failure').exists() else ''
    assert (state / 'worker-finished').exists() and (state / 'main-responsive').exists(), mode
    assert (state / 'manual-finished').exists(), 'Manual preparation was not drained'
    jobs = json.loads((state / 'jobs.json').read_text())['jobs']
    assert len(jobs) == 2 and jobs[0]['status'] == 'paused' and jobs[1]['status'] == 'pending', jobs
    pid = int((state / 'engine.pid').read_text())
    if pid:
        assert int((state / 'inactive-samples').read_text()) >= 3, 'Insufficient native focus observations'
    alive = pid and subprocess.run(['kill', '-0', str(pid)], capture_output=True).returncode == 0
    if mode.startswith('foreign') or mode == 'preexisting':
        assert alive, 'Foreign fixture content was terminated'
        # Allow only the fixture's own bounded self-cleanup, never external termination.
        deadline = time.monotonic() + 18
        while subprocess.run(['kill', '-0', str(pid)], capture_output=True).returncode == 0 and time.monotonic() < deadline:
            time.sleep(.1)
        assert subprocess.run(['kill', '-0', str(pid)], capture_output=True).returncode != 0
    else:
        assert not alive, 'Owned empty engine did not terminate: ' + err.read_text()
    results.append({'mode': mode, 'pid': pid, 'queuePreserved': True, 'drainedWithoutCancellation': True})
    print('PASS ' + mode, flush=True)
(root / 'results.json').write_text(json.dumps(results, indent=2))
print('PASS isolated AppKit termination and native PID-addressed guard: ' + str(root), flush=True)
