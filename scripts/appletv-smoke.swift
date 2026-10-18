import AppKit
import SwiftUI
import AutomationCore

@main
struct AppleTVSmoke {
    @MainActor static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        Task { @MainActor in
            do {
                let root = URL(fileURLWithPath: ProcessInfo.processInfo.environment["SUBLER_AUTOMATION_TEST_ROOT"]!)
                let source = root.appendingPathComponent("synthetic.mkv")
                let output = root.appendingPathComponent("standalone.mp4")
                let tools = try AppleTVTools.discover()
                let process = Process()
                process.executableURL = tools.ffmpeg
                process.arguments = ["-v", "error", "-f", "lavfi", "-i", "testsrc2=size=320x180:rate=24", "-t", "2", "-c:v", "mpeg4", source.path]
                process.standardError = FileHandle.nullDevice
                try process.run()
                // Only the synthetic generator runs synchronously, never the preparation/model.
                process.waitUntilExit()
                precondition(process.terminationStatus == 0)
                let original = try Data(contentsOf: source)
                let model = AppleTVPreparationModel.shared
                precondition(model.mode == .preserve && !model.isBusy && model.plan == nil)
                let host = NSHostingView(rootView: AppleTVPreparationView())
                let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 590, height: 480), styleMask: [.titled], backing: .buffered, defer: false)
                window.contentView = host
                window.orderFront(nil)
                for appearance in [NSAppearance.Name.aqua, .darkAqua] {
                    window.appearance = NSAppearance(named: appearance)
                    host.layoutSubtreeIfNeeded()
                    precondition(host.bounds.width == 590 && host.bounds.height > 0)
                }
                model.analyze(source)
                for _ in 0..<400 {
                    if !model.isBusy { break }
                    try await Task.sleep(nanoseconds: 25_000_000)
                }
                precondition(model.media != nil && model.plan == nil, "Unsupported video must not be silently copied")
                model.mode = .convert
                precondition(model.plan != nil && !model.acknowledged)
                model.start(destination: output)
                precondition(!model.isBusy && !FileManager.default.fileExists(atPath: output.path), "Consent gate must block encoding")
                model.acknowledged = true
                model.start(destination: output)
                precondition(model.isBusy)
                for _ in 0..<1200 {
                    if !model.isBusy { break }
                    try await Task.sleep(nanoseconds: 25_000_000)
                }
                precondition(!model.isBusy && model.result == output && model.fraction == 1, model.status)
                try await AppleTVPreparationService.verifyDecodableImage(output)
                let unchanged = try Data(contentsOf: source)
                precondition(unchanged == original)
                model.acknowledged = true
                model.mode = .preserve
                precondition(!model.acknowledged, "Changing the compromise must invalidate consent")
                window.close()
                print("APPLETV_MODEL_SMOKE_PASS: real SwiftUI light/dark host, default preserve, analysis, explicit conversion/consent, async encode, native image decode, original unchanged")
                app.terminate(nil)
            } catch {
                print("APPLETV_MODEL_SMOKE_FAIL: \(type(of: error))")
                exit(1)
            }
        }
        app.run()
    }
}
