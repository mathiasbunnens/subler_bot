import Foundation

/// Bundle metadata is the only version source. CLI/test runs have no app version.
public struct AppVersion {
    public static var current: AppVersion { AppVersion(infoDictionary: Bundle.main.infoDictionary) }

    private let version: String?
    private let build: String?

    public init(infoDictionary: [String: Any]?) {
        let shortVersion = (infoDictionary?["CFBundleShortVersionString"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let buildVersion = (infoDictionary?["CFBundleVersion"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        version = shortVersion.flatMap { $0.isEmpty ? nil : $0 }
        build = buildVersion.flatMap { $0.isEmpty ? nil : $0 }
    }

    public var label: String {
        guard let version else { return "Subler Automation — développement (hors bundle)" }
        return "Subler Automation v\(version)"
    }

    public var details: String {
        guard let version else { return "Version indisponible hors bundle application" }
        guard let build else { return "Version \(version) — build indisponible" }
        return "Version \(version) (build \(build))"
    }
}
