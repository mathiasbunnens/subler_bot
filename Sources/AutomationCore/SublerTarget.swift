import Foundation
import AppKit

/// Explicit process-level opt-in only. An invalid local target never falls back to
/// the user's installed Subler or shares its preferences/queue.
public struct SublerTarget: Sendable {
    public static let environmentKey = "SUBLER_AUTOMATION_LOCAL_SUBLER_APP"
    public let backgroundApplication: String?
    public init(backgroundApplication: String? = ProcessInfo.processInfo.environment[environmentKey]) {
        self.backgroundApplication = backgroundApplication
    }
    public var isBackground: Bool { backgroundApplication != nil }
    public var bundleIdentifier: String { isBackground ? "local.sublerautomation.Subler" : "org.galad.Subler" }

    public func validatedApplicationURL() throws -> URL? {
        guard let path = backgroundApplication else { return nil }
        guard path.hasPrefix("/"), path.hasSuffix(".app") else {
            throw AutomationServiceError.message("Local Subler opt-in requires an absolute .app path.")
        }
        let url = URL(fileURLWithPath: path)
        guard let bundle = Bundle(url: url), bundle.bundleIdentifier == bundleIdentifier,
              bundle.object(forInfoDictionaryKey: "SublerAutomationBackgroundProtocol") as? String == "1",
              bundle.object(forInfoDictionaryKey: "LSBackgroundOnly") as? Bool == true else {
            throw AutomationServiceError.message("Local Subler is missing or is not the reviewed background build. No installed-app fallback was attempted.")
        }
        try validateRunningApplicationURLs(NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).compactMap(\.bundleURL), expected: url)
        return url
    }

    internal func validateRunningApplicationURLs(_ running: [URL], expected: URL) throws {
        guard running.allSatisfy({ $0.resolvingSymlinksInPath() == expected.resolvingSymlinksInPath() }) else {
            throw AutomationServiceError.message("A different local Subler build is already running. Quit that idle local build explicitly before retrying; it was not terminated or used.")
        }
    }

    internal func applicationClause() throws -> String {
        if let url = try validatedApplicationURL() { return "application \(AppleScriptService.literal(url.path))" }
        return "application id \(AppleScriptService.literal(bundleIdentifier))"
    }
    internal func documentArgument(_ id: Int, role: String) -> String {
        isBackground ? "owned token \(id)" : "\(role) (document of window id \(id))"
    }
}
