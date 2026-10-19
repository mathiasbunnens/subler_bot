#!/usr/bin/env python3
"""Deterministically exercise the real Queue.swift at its last-item/idle boundary.

Only an enableSleep barrier is injected into a scratch copy. No applications,
media, persistent queues or upstream source files are touched by this test.
"""
import os
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
source = (ROOT / 'vendor-local/Subler/Classes/Queue.swift').read_text()
source = source.replace('import IOKit', 'import IOKit\nimport IOKit.pwr_mgt')
assert source.count('private func enableSleep() {') == 1
source = source.replace('private func enableSleep() {', 'private func enableSleep() {\n        TestBoundary.waitOnce()')
stubs = r'''
import Foundation
import IOKit

final class Logger {
    static let shared = Logger()
    func writeError(toLog: Error) {}
    func write(toLog: String) {}
}
final class QueueItem: NSObject, NSSecureCoding {
    static var supportsSecureCoding: Bool { true }
    required init?(coder: NSCoder) { super.init() }
    override init() { super.init() }
    func encode(with coder: NSCoder) {}
    enum Status { case ready, working, completed, failed, cancelled }
    var status = Status.ready
    var delegate: AnyObject?
    let fileURL = URL(fileURLWithPath: "/generated-queue-test")
    let localizedWorkingDescription = "Generated test"
    func process() throws {}
    func cancel() {}
}
enum TestBoundary {
    static let reached = DispatchSemaphore(value: 0)
    static let release = DispatchSemaphore(value: 0)
    static var first = true // accessed only by the serial worker
    static func waitOnce() {
        if first {
            first = false
            reached.signal()
            _ = release.wait(timeout: .now() + 5)
        }
    }
}
@main enum QueueRegression {
    static func main() {
        let queue = Queue(url: URL(fileURLWithPath: CommandLine.arguments[1]))
        let first = QueueItem(), second = QueueItem()
        queue.append(first)
        queue.start()
        guard TestBoundary.reached.wait(timeout: .now() + 5) == .success else {
            fatalError("Worker did not reach the idle boundary")
        }
        // The previous item is already completed, so a client may enqueue/start.
        queue.append(second)
        queue.start()
        TestBoundary.release.signal()
        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline && (queue.status != .completed || queue.readyCount != 0) {
            Thread.sleep(forTimeInterval: 0.01)
        }
        guard queue.status == .completed, queue.readyCount == 0 else {
            fatalError("Lost start at the completion/idle boundary; next owned item remained ready")
        }
        print("PASS: single start at last-item/idle boundary processes both owned items")
    }
}
'''
with tempfile.TemporaryDirectory(prefix='subler-queue-regression-', dir=os.environ['TMPDIR']) as temp:
    path = Path(temp)
    (path / 'Queue.swift').write_text(source)
    (path / 'Harness.swift').write_text(stubs)
    subprocess.run(['swiftc', '-swift-version', '5', path / 'Queue.swift', path / 'Harness.swift', '-o', path / 'test'], check=True)
    subprocess.run([path / 'test', path / 'queue.archive'], check=True)
