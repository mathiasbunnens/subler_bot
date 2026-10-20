import Foundation

/// Bundle metadata is the only version source. CLI/test runs have no app version.
public struct AppVersion {
    public static var current: AppVersion { AppVersion(infoDictionary: Bundle.main.infoDictionary) }

    private let version: String?
    private let build: String?
    private let name: String
    private let commit: String?
    private let sourceDirty: Bool

    public init(infoDictionary: [String: Any]?) {
        name = infoDictionary?["CFBundleDisplayName"] as? String ?? "Subler Automation"
        commit = infoDictionary?["SublerAutomationCommit"] as? String
        sourceDirty = infoDictionary?["SublerAutomationSourceDirty"] as? Bool ?? false
        let shortVersion = (infoDictionary?["CFBundleShortVersionString"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let buildVersion = (infoDictionary?["CFBundleVersion"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        version = shortVersion.flatMap { $0.isEmpty ? nil : $0 }
        build = buildVersion.flatMap { $0.isEmpty ? nil : $0 }
    }

    public var label: String {
        guard let version else { return "Subler Automation · développement (hors bundle)" }
        return "\(name) · v\(version)"
    }

    public var details: String {
        guard let version else { return "Version indisponible hors bundle application" }
        guard let build else { return "Version \(version) — build indisponible" }
        let provenance = commit.map { " · \($0.prefix(7))\(sourceDirty ? " + modifications locales" : "")" } ?? ""
        return "Version \(version) (build \(build))\(provenance)"
    }
}
