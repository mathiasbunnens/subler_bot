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
                let hdrSource = root.appendingPathComponent("pq.mkv")
                let hdrOutput = root.appendingPathComponent("pq.mp4")
                let hdrGenerator = Process()
                hdrGenerator.executableURL = tools.ffmpeg
                hdrGenerator.arguments = ["-v", "error", "-f", "lavfi", "-i", "testsrc2=size=320x180:rate=24,format=yuv420p10le,setparams=color_primaries=bt2020:color_trc=smpte2084:colorspace=bt2020nc:range=limited", "-t", "1", "-c:v", "libx265", "-x265-params", "pools=1:log-level=error:master-display=G(13250,34500)B(7500,3000)R(34000,16000)WP(15635,16450)L(40000000,50):max-cll=1100,668", hdrSource.path]
                hdrGenerator.standardError = FileHandle.nullDevice
                try hdrGenerator.run()
                hdrGenerator.waitUntilExit()
                precondition(hdrGenerator.terminationStatus == 0)
                model.analyze(hdrSource)
                for _ in 0..<400 {
                    if !model.isBusy { break }
                    try await Task.sleep(nanoseconds: 25_000_000)
                }
                precondition(model.media != nil && model.mode == .preserve && model.plan != nil)
                model.mode = .hdr10
                precondition(model.plan == nil && !model.allowDynamicHDRLoss && !model.acknowledged)
                model.acknowledged = true
                model.start(destination: hdrOutput)
                precondition(!model.isBusy, "General agreement cannot bypass separate dynamic HDR consent")
                model.allowDynamicHDRLoss = true
                precondition(model.plan != nil && !model.acknowledged)
                for appearance in [NSAppearance.Name.aqua, .darkAqua] {
                    window.appearance = NSAppearance(named: appearance)
                    host.layoutSubtreeIfNeeded()
                }
                model.acknowledged = true
                model.start(destination: hdrOutput)
                for _ in 0..<1200 {
                    if !model.isBusy { break }
                    try await Task.sleep(nanoseconds: 25_000_000)
                }
                precondition(model.result == hdrOutput && !model.isBusy, model.status)
                let hdrResult = try await AppleTVPreparationService.inspect(source: hdrOutput)
                try AppleTVPlan.validateHDR10Output(source: model.media!, output: hdrResult)
                model.mode = .preserve
                precondition(!model.allowDynamicHDRLoss && !model.acknowledged)
                window.close()
                print("APPLETV_MODEL_SMOKE_PASS: real SwiftUI light/dark host, default preserve, SDR/HDR10 encoding, separate dynamic HDR consent/reset, native decode, static HDR metadata validation, original unchanged")
                app.terminate(nil)
            } catch {
                print("APPLETV_MODEL_SMOKE_FAIL: \(type(of: error))")
                exit(1)
            }
        }
        app.run()
    }
}
