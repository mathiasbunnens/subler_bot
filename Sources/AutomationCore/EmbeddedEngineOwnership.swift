import Foundation
import AppKit
import Carbon

internal struct EngineProcessIdentity: Equatable {
    let pid: pid_t
    let launched: Date
    let url: URL
    init(pid: pid_t, launched: Date, url: URL) {
        self.pid = pid; self.launched = launched
        self.url = url.resolvingSymlinksInPath().standardizedFileURL
    }
    init?(_ app: NSRunningApplication) {
        guard let date = app.launchDate, let url = app.bundleURL else { return nil }
        self.init(pid: app.processIdentifier, launched: date, url: url)
    }
}

internal struct EmbeddedEngineOwnership {
    private var launched: EngineProcessIdentity?
    mutating func recordLaunch(_ process: EngineProcessIdentity) { launched = process }
    func permitsShutdown(expected: URL, running: [EngineProcessIdentity]) -> Bool {
        guard running.count == 1, let launched, running[0] == launched else { return false }
        return launched.url == expected.resolvingSymlinksInPath().standardizedFileURL
    }
}

/// Shared with permission preparation; never adopts an engine that already existed.
@MainActor
internal enum EmbeddedEngineLifetime {
    static var ownership = EmbeddedEngineOwnership()
}

extension SublerTarget {
    @MainActor
    internal func quitEmbeddedIfOwnedAndIdle(ownedQueueIDs: Set<String>) async -> String {
        let caller = Bundle.main
        guard caller.object(forInfoDictionaryKey: "SublerAutomationBackgroundRelativePath") as? String == "Contents/Helpers/Subler Background.app",
              let path = backgroundApplication,
              URL(fileURLWithPath: path).resolvingSymlinksInPath() == caller.bundleURL.resolvingSymlinksInPath()
                .appendingPathComponent("Contents/Helpers/Subler Background.app").standardizedFileURL else {
            return "Moteur conservé : cible non embarquée."
        }
        let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
        guard !running.isEmpty else { return "Moteur absent : aucune action." }
        do {
            guard let expected = try validatedApplicationURL(),
                  running.count == 1,
                  let identity = EngineProcessIdentity(running[0]),
                  EmbeddedEngineLifetime.ownership.permitsShutdown(expected: expected, running: [identity]),
                  Bundle(url: expected)?.object(forInfoDictionaryKey: "SublerAutomationGracefulQuitProtocol") as? String == "1" else {
                return "Moteur conservé : instance non créée par cette session, ambiguë, ou protocole d’arrêt absent."
            }
            let app = running[0]
            let pid = identity.pid
            let ids = ownedQueueIDs.sorted().joined(separator: "\n")
            // Direct PID addressing cannot launch an absent target or resolve a different
            // LaunchServices registration. Never send a standard/global quit event.
            let response = await Task.detached { () -> String in
                func code(_ text: String) -> UInt32 { text.utf8.reduce(0) { ($0 << 8) | UInt32($1) } }
                let event = NSAppleEventDescriptor(eventClass: code("Subl"), eventID: code("BgQt"),
                    targetDescriptor: NSAppleEventDescriptor(processIdentifier: pid),
                    returnID: AEReturnID(kAutoGenerateReturnID), transactionID: AETransactionID(kAnyTransactionID))
                event.setParam(NSAppleEventDescriptor(string: ids), forKeyword: AEKeyword(keyDirectObject))
                do {
                    let reply = try event.sendEvent(options: [.waitForReply, .neverInteract], timeout: 10)
                    if let error = reply.paramDescriptor(forKeyword: AEKeyword(keyErrorNumber)), error.int32Value != 0 {
                        return "Apple Event refusé (\(error.int32Value))."
                    }
                    return reply.paramDescriptor(forKeyword: AEKeyword(keyDirectObject))?.stringValue ?? "Réponse inconnue."
                } catch { return error.localizedDescription }
            }.value
            // A successful native terminate may close the AE connection before replying.
            // Only observing the exact launched process exit counts as success.
            let deadline = Date().addingTimeInterval(5)
            while !app.isTerminated && Date() < deadline {
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
            return app.isTerminated ? "Moteur embarqué de cette session quitté proprement." : "Moteur conservé : \(response)"
        } catch { return "Moteur conservé : \(error.localizedDescription)" }
    }
}
