import Foundation
import AppKit

/// Signed bundle selection takes precedence; environment opt-in remains available
/// for development. Invalid local configuration never falls back to installed Subler.
public struct SublerTarget: Sendable {
    public static let environmentKey = "SUBLER_AUTOMATION_LOCAL_SUBLER_APP"
    public let backgroundApplication: String?
    public init() {
        self.init(environment: ProcessInfo.processInfo.environment,
                  bundleInfo: Bundle.main.infoDictionary, bundleURL: Bundle.main.bundleURL)
    }
    public init(environment: [String: String], bundleInfo: [String: Any]?, bundleURL: URL) {
        if bundleInfo?["SublerAutomationEngine"] != nil || bundleInfo?["SublerAutomationBackgroundRelativePath"] != nil {
            // A present but malformed/unknown configuration is deliberately invalid,
            // not the absence of opt-in. Only the reviewed co-local sibling is allowed.
            if bundleInfo?["SublerAutomationEngine"] as? String == "background",
               bundleInfo?["SublerAutomationBackgroundRelativePath"] as? String == "../Subler Background.app" {
                backgroundApplication = bundleURL.deletingLastPathComponent()
                    .appendingPathComponent("Subler Background.app").standardizedFileURL.path
            } else {
                backgroundApplication = ""
            }
        } else {
            backgroundApplication = environment[Self.environmentKey]
        }
    }
    public init(backgroundApplication: String?) {
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
              bundle.object(forInfoDictionaryKey: "SublerAutomationBackgroundProtocol") as? String == "2",
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
    internal func documentArgument(_ document: SublerDocument, role: String) throws -> String {
        if isBackground {
            guard let token = document.backgroundToken, UUID(uuidString: token) != nil else {
                throw AutomationServiceError.message("Background document requires an owned UUID token.")
            }
            return "owned token \(AppleScriptService.literal(token))"
        }
        return "\(role) (document of window id \(document.id))"
    }
}
